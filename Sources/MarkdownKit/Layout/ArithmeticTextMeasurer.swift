//
//  ArithmeticTextMeasurer.swift
//  MarkdownKit
//

import Foundation
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ArithmeticTextMeasurer {

    fileprivate struct RawFontLineMetrics: Equatable {
        let ascent: CGFloat
        let descent: CGFloat
        let leading: CGFloat
    }

    fileprivate enum FontLineMetricSet {
        case one(RawFontLineMetrics)
        case two(RawFontLineMetrics, RawFontLineMetrics)
        case many([RawFontLineMetrics])

        init(_ metrics: [RawFontLineMetrics]) {
            precondition(!metrics.isEmpty)
            switch metrics.count {
            case 1:
                self = .one(metrics[0])
            case 2:
                self = .two(metrics[0], metrics[1])
            default:
                self = .many(metrics)
            }
        }

        func scaled(by lineHeightMultiple: CGFloat) -> (height: CGFloat, baselineOffset: CGFloat) {
            var baselineOffset: CGFloat = 0
            var belowBaseline: CGFloat = 0

            func include(_ metrics: RawFontLineMetrics) {
                baselineOffset = max(
                    baselineOffset,
                    metrics.ascent * lineHeightMultiple
                )
                belowBaseline = max(
                    belowBaseline,
                    metrics.descent * lineHeightMultiple + metrics.leading
                )
            }

            switch self {
            case let .one(metrics):
                include(metrics)
            case let .two(first, second):
                include(first)
                include(second)
            case let .many(metrics):
                for metric in metrics {
                    include(metric)
                }
            }

            return (baselineOffset + belowBaseline, baselineOffset)
        }
    }

    fileprivate struct CachedSegmentMeasurement {
        let width: CGFloat
        let fontMetrics: FontLineMetricSet?
        let containsRequestedFontRun: Bool?
        let containsVisibleCharacter: Bool?
    }

    private struct FontCacheKey: Hashable {
        let fontName: String
        let pointSizeMilli: Int
    }

    private struct PreparedFontMeasurement {
        let cacheKey: FontCacheKey
        let ctFont: CTFont
        let baseLineHeight: CGFloat
        let rawLineMetrics: RawFontLineMetrics
    }

    /// Per-preparation memoization avoids rebuilding identical CoreText fonts and
    /// repeatedly taking the shared width-cache lock for the many repeated runs
    /// and tokens emitted by list/blockquote builders. The shared cache remains
    /// the source of cross-preparation reuse and keeps its exact key/FIFO contract.
    private final class PreparationCache {
        private var fonts: [Font: PreparedFontMeasurement] = [:]
        private var segments: [WidthCache.Key: CachedSegmentMeasurement] = [:]

        init(estimatedSegmentCount: Int) {
            fonts.reserveCapacity(8)
            segments.reserveCapacity(max(0, estimatedSegmentCount))
        }

        func fontMeasurement(for font: Font) -> PreparedFontMeasurement {
            if let cached = fonts[font] {
                return cached
            }

            let ctFont = ArithmeticTextMeasurer.ctFont(from: font)
            #if canImport(UIKit)
            let baseLineHeight = font.lineHeight
            #elseif canImport(AppKit)
            let baseLineHeight = ArithmeticTextMeasurer.defaultLineHeight(for: font)
            #endif
            let measurement = PreparedFontMeasurement(
                cacheKey: ArithmeticTextMeasurer.fontCacheKey(for: font),
                ctFont: ctFont,
                baseLineHeight: baseLineHeight,
                rawLineMetrics: ArithmeticTextMeasurer.baseFontLineMetrics(
                    for: font,
                    ctFont: ctFont
                )
            )
            fonts[font] = measurement
            return measurement
        }

        func segmentMeasurement(
            for key: WidthCache.Key,
            text: String,
            ctFont: CTFont,
            baseFontLineMetrics: RawFontLineMetrics
        ) -> CachedSegmentMeasurement {
            if let cached = segments[key] {
                return cached
            }

            let measurement: CachedSegmentMeasurement
            if let cached = ArithmeticTextMeasurer.cachedWidths.measurement(for: key),
               cached.fontMetrics != nil,
               cached.containsRequestedFontRun != nil,
               cached.containsVisibleCharacter != nil {
                measurement = cached
            } else {
                measurement = ArithmeticTextMeasurer.shapedMeasurement(
                    for: text,
                    ctFont: ctFont,
                    baseFontLineMetrics: baseFontLineMetrics
                )
                ArithmeticTextMeasurer.cachedWidths.insert(measurement, for: key)
            }
            segments[key] = measurement
            return measurement
        }
    }

    private struct ParagraphUTF16Range {
        let contentRange: NSRange
        let separatorRange: NSRange?
        let styleSourceLocation: Int
        let emptyLineFontSourceLocation: Int
    }

    private struct ParagraphMetrics {
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let paragraphSpacingBefore: CGFloat
        let paragraphSpacingAfter: CGFloat
        let lineHeightMultiple: CGFloat
        let emptyLineHeight: CGFloat
    }

    private struct DiscretionaryHyphenMeasurement {
        let advance: CGFloat
        let containsRequestedFontRun: Bool
    }

    /// Bounded, lock-owned width cache keyed by a structured `Hashable` type.
    ///
    /// Replaces the former `NSCache<NSString, NSNumber>`: no per-lookup string
    /// interpolation, no `NSString` bridging, and no `NSNumber` boxing. Widths are
    /// stored as direct `CGFloat` values behind a single `NSLock`.
    ///
    /// Eviction is a strict O(1) FIFO ring: once `capacity` distinct keys have been
    /// inserted, each further new key evicts the oldest surviving key in insertion
    /// order. Updating an existing key's value never consumes a new ring slot and
    /// never changes eviction order. `@unchecked Sendable`: all mutable state
    /// (`storage`, `ring`, `writeIndex`) is guarded by `lock`.
    final class WidthCache: @unchecked Sendable {

        struct Key: Hashable {
            let fontName: String
            let pointSizeMilli: Int
            let text: String

            init(fontName: String, pointSizeMilli: Int, text: String) {
                self.fontName = fontName
                self.pointSizeMilli = pointSizeMilli
                self.text = text
            }

            /// Compares `fontName` and `text` by their exact UTF-8 code-unit
            /// sequence rather than Swift's canonical-equivalence `String`
            /// comparison, so precomposed and decomposed forms of the same
            /// grapheme (for example `"é"` vs. `"e\u{301}"`) remain distinct
            /// cache identities — matching the exact-encoding sensitivity the
            /// prior `NSString`-bridged key relied on, without bridging to
            /// `NSString` or allocating an intermediate array.
            static func == (lhs: Key, rhs: Key) -> Bool {
                lhs.pointSizeMilli == rhs.pointSizeMilli
                    && lhs.fontName.utf8.elementsEqual(rhs.fontName.utf8)
                    && lhs.text.utf8.elementsEqual(rhs.text.utf8)
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(pointSizeMilli)
                Self.combineUTF8(fontName, into: &hasher)
                Self.combineUTF8(text, into: &hasher)
            }

            /// Hashes `string`'s exact UTF-8 code-unit sequence: the length is
            /// combined first so that, for example, `fontName: "AB", text: "C"`
            /// cannot be crafted to collide with `fontName: "A", text: "BC"`.
            /// Uses the contiguous-storage fast path (one `combine(bytes:)` call)
            /// when available, falling back to a per-byte loop otherwise — never
            /// bridging to `NSString` or allocating an intermediate array.
            private static func combineUTF8(_ string: String, into hasher: inout Hasher) {
                let utf8View = string.utf8
                hasher.combine(utf8View.count)
                let usedFastPath = utf8View.withContiguousStorageIfAvailable { buffer in
                    hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
                    return true
                }
                if usedFastPath != true {
                    for byte in utf8View {
                        hasher.combine(byte)
                    }
                }
            }
        }

        let capacity: Int

        private let lock = NSLock()
        private var storage: [Key: CachedSegmentMeasurement] = [:]
        /// Grows by `append` up to `capacity`, then is overwritten in place at
        /// `writeIndex` — never eagerly pre-allocated to the full bound.
        private var ring: [Key] = []
        private var writeIndex = 0

        #if canImport(UIKit)
        private var memoryWarningObserver: NSObjectProtocol?
        #elseif canImport(AppKit)
        private var memoryPressureSource: DispatchSourceMemoryPressure?
        #endif

        /// - Parameter observesMemoryPressure: When `true`, registers a
        ///   platform memory-pressure callback that calls `removeAll()`,
        ///   restoring the purge-under-pressure behavior the prior
        ///   `NSCache`-backed implementation provided for free. Defaults to
        ///   `false` so ad hoc/test caches never register global observers;
        ///   the shared production cache opts in explicitly.
        init(capacity: Int, observesMemoryPressure: Bool = false) {
            self.capacity = max(0, capacity)
            guard observesMemoryPressure else { return }
            #if canImport(UIKit)
            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.removeAll()
            }
            #elseif canImport(AppKit)
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.removeAll()
            }
            source.resume()
            memoryPressureSource = source
            #endif
        }

        deinit {
            #if canImport(UIKit)
            if let memoryWarningObserver {
                NotificationCenter.default.removeObserver(memoryWarningObserver)
            }
            #elseif canImport(AppKit)
            memoryPressureSource?.cancel()
            #endif
        }

        /// Returns the cached width for `key`, or `nil` on a miss. Hits do not
        /// promote position: the FIFO order is determined solely by insertion.
        func value(for key: Key) -> CGFloat? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]?.width
        }

        fileprivate func measurement(for key: Key) -> CachedSegmentMeasurement? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }

        /// Stores `width` for `key`. A non-positive `capacity` retains nothing.
        /// Updating an existing key overwrites its value in place without
        /// consuming a ring slot or altering eviction order. A new key is
        /// appended while the ring is still filling; once full, it evicts the
        /// oldest surviving key at `writeIndex`.
        func insert(_ width: CGFloat, for key: Key) {
            insert(
                CachedSegmentMeasurement(
                    width: width,
                    fontMetrics: nil,
                    containsRequestedFontRun: nil,
                    containsVisibleCharacter: nil
                ),
                for: key
            )
        }

        fileprivate func insert(_ measurement: CachedSegmentMeasurement, for key: Key) {
            guard capacity > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            if let existing = storage[key] {
                storage[key] = CachedSegmentMeasurement(
                    width: measurement.width,
                    fontMetrics: measurement.fontMetrics ?? existing.fontMetrics,
                    containsRequestedFontRun: measurement.containsRequestedFontRun
                        ?? existing.containsRequestedFontRun,
                    containsVisibleCharacter: measurement.containsVisibleCharacter
                        ?? existing.containsVisibleCharacter
                )
                return
            }
            storage[key] = measurement
            if ring.count < capacity {
                ring.append(key)
                return
            }
            let evicted = ring[writeIndex]
            storage.removeValue(forKey: evicted)
            ring[writeIndex] = key
            writeIndex += 1
            if writeIndex == capacity {
                writeIndex = 0
            }
        }

        /// Clears all cached entries and resets FIFO eviction state, as if the
        /// cache had just been created. Invoked automatically under platform
        /// memory pressure when `observesMemoryPressure` was `true` at init.
        func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAll()
            ring.removeAll()
            writeIndex = 0
        }

        // MARK: - Test diagnostics (internal; accessible via @testable)

        var countForTesting: Int {
            lock.lock(); defer { lock.unlock() }
            return storage.count
        }
    }

    private static let cachedWidths = WidthCache(capacity: 50_000, observesMemoryPressure: true)
    #if canImport(UIKit)
    static let defaultTextKitFont: Font =
        Font(name: "Helvetica", size: 12) ?? Font.systemFont(ofSize: 12)
    #elseif canImport(AppKit)
    static nonisolated(unsafe) let defaultTextKitFont: Font =
        Font(name: "Helvetica", size: 12)
            ?? Font.userFont(ofSize: 12)
            ?? Font.systemFont(ofSize: 12)
    #endif
    #if canImport(AppKit)
    private static let cachedDefaultLineMetrics = DefaultLineMetricsCache(capacity: 256)
    #endif

    static func prepare(attributedString: NSAttributedString) -> ArithmeticTextCalculator.PreparedText {
        var preparedText = ArithmeticTextCalculator.PreparedText()
        let fullString = attributedString.string
        let fullNSString = fullString as NSString
        let utf16Characters = Array(fullString.utf16)
        let estimatedSegmentCount = min(max(utf16Characters.count / 4, 8), 8_192)
        preparedText.reserveCapacity(
            segments: estimatedSegmentCount,
            paragraphs: min(max(utf16Characters.count / 40, 1), 512)
        )
        let preparationCache = PreparationCache(
            estimatedSegmentCount: min(max(estimatedSegmentCount / 4, 8), 512)
        )

        if !utf16Characters.isEmpty,
           !utf16Characters.contains(where: isParagraphSeparator) {
            prepareParagraph(
                ParagraphUTF16Range(
                    contentRange: NSRange(location: 0, length: utf16Characters.count),
                    separatorRange: nil,
                    styleSourceLocation: 0,
                    emptyLineFontSourceLocation: 0
                ),
                attributedString: attributedString,
                fullString: fullNSString,
                utf16: utf16Characters,
                preparationCache: preparationCache,
                preparedText: &preparedText
            )
            return preparedText
        }

        prepareParagraphs(
            in: fullNSString,
            attributedString: attributedString,
            utf16: utf16Characters,
            preparationCache: preparationCache,
            preparedText: &preparedText
        )

        return preparedText
    }

    private static func isParagraphSeparator(_ character: unichar) -> Bool {
        switch character {
        case 0x000A, 0x000D, 0x2029:
            return true
        default:
            return false
        }
    }

    private static func prepareParagraph(
        _ paragraph: ParagraphUTF16Range,
        attributedString: NSAttributedString,
        fullString: NSString,
        utf16: [unichar],
        preparationCache: PreparationCache,
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        let paragraphStartChunk = preparedText.chunks.count
        var resolvedMetrics: ParagraphMetrics?

        if paragraph.contentRange.length > 0 {
            attributedString.enumerateAttributes(in: paragraph.contentRange, options: []) { attributes, range, _ in
                let metrics = resolvedMetrics ?? paragraphMetrics(
                    for: paragraph,
                    styleAttributes: attributes,
                    fontAttributes: paragraph.emptyLineFontSourceLocation == paragraph.styleSourceLocation
                        ? attributes
                        : attributedString.attributes(
                            at: paragraph.emptyLineFontSourceLocation,
                            effectiveRange: nil
                        ),
                    preparationCache: preparationCache
                )
                resolvedMetrics = metrics
                prepareRun(
                    attributes: attributes,
                    range: range,
                    fullString: fullString,
                    utf16: utf16,
                    paragraphLineHeightMultiple: metrics.lineHeightMultiple,
                    cachedLineHeight: range.location == paragraph.contentRange.location
                        ? metrics.emptyLineHeight
                        : nil,
                    preparationCache: preparationCache,
                    preparedText: &preparedText
                )
            }
        }

        let metrics = resolvedMetrics ?? paragraphMetrics(
            for: paragraph,
            in: attributedString,
            preparationCache: preparationCache
        )

        if let separatorRange = paragraph.separatorRange {
            let separatorAttributes = attributedString.attributes(at: separatorRange.location, effectiveRange: nil)
            let separatorFont = font(from: separatorAttributes)
            let separatorMeasurement = preparationCache.fontMeasurement(for: separatorFont)
            preparedText.append(
                width: 0,
                kind: .hardBreak,
                height: separatorMeasurement.baseLineHeight * metrics.lineHeightMultiple
            )
        }

        let paragraphEntry = ArithmeticTextCalculator.Paragraph(
            chunkRange: paragraphStartChunk..<preparedText.chunks.count,
            firstLineHeadIndent: metrics.firstLineHeadIndent,
            headIndent: metrics.headIndent,
            paragraphSpacingBefore: metrics.paragraphSpacingBefore,
            paragraphSpacingAfter: metrics.paragraphSpacingAfter,
            emptyLineHeight: metrics.emptyLineHeight
        )
        preparedText.paragraphs.append(paragraphEntry)

        if preparedText.paragraphs.count == 1 {
            preparedText.headIndent = metrics.headIndent
            preparedText.firstLineHeadIndent = metrics.firstLineHeadIndent
        }
    }

    private static func prepareRun(
        attributes: [NSAttributedString.Key: Any],
        range: NSRange,
        fullString: NSString,
        utf16: [unichar],
        paragraphLineHeightMultiple: CGFloat,
        cachedLineHeight: CGFloat?,
        preparationCache: PreparationCache,
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        let font = font(from: attributes)
        let fontMeasurement = preparationCache.fontMeasurement(for: font)
        let fontCacheKey = fontMeasurement.cacheKey
        let ctFont = fontMeasurement.ctFont
        let lineHeight = cachedLineHeight
            ?? fontMeasurement.baseLineHeight * paragraphLineHeightMultiple
        let baseFontLineMetrics = FontLineMetricSet.one(
            fontMeasurement.rawLineMetrics
        ).scaled(by: paragraphLineHeightMultiple)

        let runStartSegmentIndex = preparedText.widths.count
        var scanner = ArithmeticTextScanner(utf16: utf16, range: range)

        while let span = scanner.next() {
            switch span.kind {
            case .text:
                let textRanges = ArithmeticTextSegmentClassifierMerger.classifyAndMerge(
                    textRange: span.range,
                    in: fullString,
                    utf16: utf16
                )
                for textRange in textRanges {
                    appendMeasuredSegment(
                        range: textRange,
                        kind: .text,
                        fullString: fullString,
                        ctFont: ctFont,
                        fontKey: fontCacheKey,
                        baseFontLineMetrics: fontMeasurement.rawLineMetrics,
                        lineHeight: lineHeight,
                        lineHeightMultiple: paragraphLineHeightMultiple,
                        preparationCache: preparationCache,
                        preparedText: &preparedText
                    )
                }
            case .space:
                appendMeasuredSegment(
                    range: span.range,
                    kind: .space,
                    fullString: fullString,
                    ctFont: ctFont,
                    fontKey: fontCacheKey,
                    baseFontLineMetrics: fontMeasurement.rawLineMetrics,
                    lineHeight: lineHeight,
                    lineHeightMultiple: paragraphLineHeightMultiple,
                    preparationCache: preparationCache,
                    preparedText: &preparedText
                )
            case .softHyphen:
                let discretionaryHyphen = discretionaryHyphenMeasurement(
                    preparedText: preparedText,
                    runStartSegmentIndex: runStartSegmentIndex,
                    ctFont: ctFont,
                    fontKey: fontCacheKey,
                    baseFontLineMetrics: fontMeasurement.rawLineMetrics,
                    preparationCache: preparationCache
                )
                preparedText.append(
                    width: 0,
                    kind: .softHyphen,
                    height: baseFontLineMetrics.height,
                    baselineOffset: baseFontLineMetrics.baselineOffset,
                    containsRequestedFontRun: discretionaryHyphen.containsRequestedFontRun,
                    lineEndFitAdvance: discretionaryHyphen.advance,
                    lineEndPaintAdvance: discretionaryHyphen.advance
                )
            case .hardBreak:
                preparedText.append(width: 0, kind: .hardBreak, height: lineHeight)
            }
        }
    }

    private static func prepareParagraphs(
        in string: NSString,
        attributedString: NSAttributedString,
        utf16: [unichar],
        preparationCache: PreparationCache,
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        let stringLength = string.length
        guard stringLength > 0 else { return }

        var nextParagraphLocation = 0
        var lastSeparatorRange: NSRange?
        var lastStyleSourceLocation = 0

        while nextParagraphLocation < stringLength {
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            string.getParagraphStart(
                &paragraphStart,
                end: &paragraphEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: nextParagraphLocation, length: 0)
            )

            let contentRange = NSRange(
                location: paragraphStart,
                length: contentsEnd - paragraphStart
            )
            let separatorRange = contentsEnd < paragraphEnd
                ? NSRange(location: contentsEnd, length: paragraphEnd - contentsEnd)
                : nil
            let styleSourceLocation = contentRange.length > 0
                ? contentRange.location
                : (separatorRange?.location ?? contentRange.location)

            prepareParagraph(
                ParagraphUTF16Range(
                    contentRange: contentRange,
                    separatorRange: separatorRange,
                    styleSourceLocation: styleSourceLocation,
                    emptyLineFontSourceLocation: styleSourceLocation
                ),
                attributedString: attributedString,
                fullString: string,
                utf16: utf16,
                preparationCache: preparationCache,
                preparedText: &preparedText
            )

            lastSeparatorRange = separatorRange
            lastStyleSourceLocation = styleSourceLocation
            nextParagraphLocation = paragraphEnd
        }

        if let lastSeparatorRange, nextParagraphLocation == stringLength {
            prepareParagraph(
                ParagraphUTF16Range(
                    contentRange: NSRange(location: stringLength, length: 0),
                    separatorRange: nil,
                    styleSourceLocation: lastStyleSourceLocation,
                    emptyLineFontSourceLocation: NSMaxRange(lastSeparatorRange) - 1
                ),
                attributedString: attributedString,
                fullString: string,
                utf16: utf16,
                preparationCache: preparationCache,
                preparedText: &preparedText
            )
        }
    }

    private static func paragraphMetrics(
        for paragraph: ParagraphUTF16Range,
        in attributedString: NSAttributedString,
        preparationCache: PreparationCache
    ) -> ParagraphMetrics {
        let styleAttributes = attributedString.attributes(
            at: paragraph.styleSourceLocation,
            effectiveRange: nil
        )
        let fontAttributes = paragraph.emptyLineFontSourceLocation == paragraph.styleSourceLocation
            ? styleAttributes
            : attributedString.attributes(
                at: paragraph.emptyLineFontSourceLocation,
                effectiveRange: nil
            )

        return paragraphMetrics(
            for: paragraph,
            styleAttributes: styleAttributes,
            fontAttributes: fontAttributes,
            preparationCache: preparationCache
        )
    }

    private static func paragraphMetrics(
        for paragraph: ParagraphUTF16Range,
        styleAttributes: [NSAttributedString.Key: Any],
        fontAttributes: [NSAttributedString.Key: Any],
        preparationCache: PreparationCache
    ) -> ParagraphMetrics {
        let paragraphStyle = styleAttributes[.paragraphStyle] as? NSParagraphStyle
        let lineHeightMultiple = effectiveLineHeightMultiple(from: paragraphStyle)
        let emptyLineFont = font(from: fontAttributes)
        let emptyLineFontMeasurement = preparationCache.fontMeasurement(for: emptyLineFont)

        return ParagraphMetrics(
            firstLineHeadIndent: nonnegativeFiniteMetric(paragraphStyle?.firstLineHeadIndent),
            headIndent: nonnegativeFiniteMetric(paragraphStyle?.headIndent),
            paragraphSpacingBefore: nonnegativeFiniteMetric(paragraphStyle?.paragraphSpacingBefore),
            paragraphSpacingAfter: paragraph.separatorRange == nil
                ? 0
                : nonnegativeFiniteMetric(paragraphStyle?.paragraphSpacing),
            lineHeightMultiple: lineHeightMultiple,
            emptyLineHeight: emptyLineFontMeasurement.baseLineHeight * lineHeightMultiple
        )
    }

    private static func nonnegativeFiniteMetric(_ value: CGFloat?) -> CGFloat {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return value
    }

    private static func effectiveLineHeightMultiple(from paragraphStyle: NSParagraphStyle?) -> CGFloat {
        let multiple = paragraphStyle?.lineHeightMultiple ?? 0
        return multiple.isFinite && multiple > 0 ? multiple : 1
    }

    private static func font(from attributes: [NSAttributedString.Key: Any]) -> Font {
        (attributes[.font] as? Font) ?? defaultTextKitFont
    }

    private static func fontCacheKey(for font: Font) -> FontCacheKey {
        guard let pointSizeMilli = arithmeticPointSizeMilli(font.pointSize) else {
            preconditionFailure("Arithmetic preparation requires a finite, positive, cacheable font point size")
        }
        return FontCacheKey(
            fontName: font.fontName,
            pointSizeMilli: pointSizeMilli
        )
    }

    static func supportsArithmeticPointSize(_ pointSize: CGFloat) -> Bool {
        arithmeticPointSizeMilli(pointSize) != nil
    }

    private static func arithmeticPointSizeMilli(_ pointSize: CGFloat) -> Int? {
        guard pointSize.isFinite, pointSize > 0 else { return nil }
        let scaledPointSize = (pointSize * 1000).rounded()
        guard scaledPointSize.isFinite else { return nil }
        return Int(exactly: scaledPointSize)
    }

    private static func layoutLineHeight(
        for font: Font,
        lineHeightMultiple: CGFloat
    ) -> CGFloat {
        #if canImport(UIKit)
        let baseLineHeight = font.lineHeight
        #elseif canImport(AppKit)
        let baseLineHeight = defaultLineHeight(for: font)
        #endif
        return baseLineHeight * lineHeightMultiple
    }

    #if canImport(AppKit)
    private struct DefaultLineMetrics {
        let height: CGFloat
        let baselineOffset: CGFloat
    }

    private final class DefaultLineMetricsCache: @unchecked Sendable {
        private let capacity: Int
        private let lock = NSLock()
        private var storage: [Font: DefaultLineMetrics] = [:]
        private var ring: [Font] = []
        private var writeIndex = 0

        init(capacity: Int) {
            self.capacity = max(0, capacity)
        }

        func value(for font: Font) -> DefaultLineMetrics {
            lock.lock()
            if let cachedMetrics = storage[font] {
                lock.unlock()
                return cachedMetrics
            }
            lock.unlock()

            let measuredMetrics = CoreTextLayoutSafetyGate.withLock {
                let layoutManager = NSLayoutManager()
                return DefaultLineMetrics(
                    height: layoutManager.defaultLineHeight(for: font),
                    baselineOffset: layoutManager.defaultBaselineOffset(for: font)
                )
            }
            guard capacity > 0 else { return measuredMetrics }

            lock.lock()
            defer { lock.unlock() }
            if let cachedMetrics = storage[font] {
                return cachedMetrics
            }
            if ring.count < capacity {
                ring.append(font)
            } else {
                storage.removeValue(forKey: ring[writeIndex])
                ring[writeIndex] = font
                writeIndex = (writeIndex + 1) % capacity
            }
            storage[font] = measuredMetrics
            return measuredMetrics
        }
    }

    private static func defaultLineMetrics(for font: Font) -> DefaultLineMetrics {
        cachedDefaultLineMetrics.value(for: font)
    }

    private static func defaultLineHeight(for font: Font) -> CGFloat {
        defaultLineMetrics(for: font).height
    }
    #endif

    private static func appendMeasuredSegment(
        range: NSRange,
        kind: ArithmeticTextCalculator.SegmentKind,
        fullString: NSString,
        ctFont: CTFont,
        fontKey: FontCacheKey,
        baseFontLineMetrics: RawFontLineMetrics,
        lineHeight: CGFloat,
        lineHeightMultiple: CGFloat,
        preparationCache: PreparationCache,
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        guard range.length > 0 else { return }

        let segmentText = fullString.substring(with: range)
        let key = widthCacheKey(for: segmentText, fontKey: fontKey)
        let measurement = preparationCache.segmentMeasurement(
            for: key,
            text: segmentText,
            ctFont: ctFont,
            baseFontLineMetrics: baseFontLineMetrics
        )

        let metrics = measurement.fontMetrics?.scaled(by: lineHeightMultiple)
        append(
            width: measurement.width,
            kind: kind,
            text: segmentText,
            ctFont: ctFont,
            lineHeight: metrics?.height ?? lineHeight,
            baselineOffset: metrics?.baselineOffset,
            containsRequestedFontRun: measurement.containsRequestedFontRun ?? true,
            containsVisibleCharacter: measurement.containsVisibleCharacter
                ?? (kind == .text),
            preparedText: &preparedText
        )
    }

    private static func append(
        width: CGFloat,
        kind: ArithmeticTextCalculator.SegmentKind,
        text: String,
        ctFont: CTFont,
        lineHeight: CGFloat,
        baselineOffset: CGFloat? = nil,
        containsRequestedFontRun: Bool = true,
        containsVisibleCharacter: Bool = true,
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        preparedText.append(
            width: width,
            kind: kind,
            height: lineHeight,
            text: kind == .text ? text : "",
            ctFont: kind == .text ? ctFont : nil,
            baselineOffset: baselineOffset,
            containsRequestedFontRun: containsRequestedFontRun,
            containsVisibleCharacter: kind == .text && containsVisibleCharacter
        )
    }

    /// Uses the same visibility contract as AppKit profile routing: whitespace
    /// and default-ignorable scalars neither create a fallback-only line nor
    /// provide requested-font evidence for another visible glyph.
    static func containsVisibleCharacter(
        in string: NSString,
        range: NSRange
    ) -> Bool {
        guard range.length > 0 else { return false }
        if range.length == 1,
           let scalar = UnicodeScalar(UInt32(string.character(at: range.location))) {
            return isVisible(scalar)
        }
        return string.substring(with: range).unicodeScalars.contains(where: isVisible)
    }

    /// Tests the Unicode scalar that owns one UTF-16 code unit. Both halves of a
    /// surrogate pair inherit the scalar's visibility, while whitespace and
    /// default-ignorables remain ineligible as requested-font glyph evidence.
    static func isVisibleUTF16CodeUnit(in string: NSString, at index: Int) -> Bool {
        guard index >= 0, index < string.length else { return false }
        let codeUnit = string.character(at: index)
        let scalarValue: UInt32

        if (0xD800...0xDBFF).contains(codeUnit), index + 1 < string.length {
            let low = string.character(at: index + 1)
            guard (0xDC00...0xDFFF).contains(low) else { return false }
            scalarValue = 0x10000
                + (UInt32(codeUnit) - 0xD800) * 0x400
                + (UInt32(low) - 0xDC00)
        } else if (0xDC00...0xDFFF).contains(codeUnit), index > 0 {
            let high = string.character(at: index - 1)
            guard (0xD800...0xDBFF).contains(high) else { return false }
            scalarValue = 0x10000
                + (UInt32(high) - 0xD800) * 0x400
                + (UInt32(codeUnit) - 0xDC00)
        } else {
            scalarValue = UInt32(codeUnit)
        }

        guard let scalar = UnicodeScalar(scalarValue) else { return false }
        return isVisible(scalar)
    }

    private static func isVisible(_ scalar: UnicodeScalar) -> Bool {
        !scalar.properties.isWhitespace
            && !scalar.properties.isDefaultIgnorableCodePoint
    }

    /// Returns true only when the requested font supplies a nonzero glyph whose
    /// CoreText string index belongs to a visible extended grapheme inside
    /// `sourceRange`. Run presence alone is insufficient: CoreText commonly
    /// retains the requested font for NBSP/default-ignorable glue next to a
    /// fallback-only emoji or symbol.
    static func requestedFontSuppliesVisibleGlyph(
        in line: CTLine,
        string: NSString,
        requestedFont: CTFont,
        sourceRange: NSRange
    ) -> Bool {
        guard sourceRange.length > 0 else { return false }

        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            guard CFEqual(runFont, requestedFont) else {
                continue
            }

            let runCFRange = CTRunGetStringRange(run)
            guard runCFRange.location != kCFNotFound,
                  runCFRange.location >= 0,
                  runCFRange.length > 0 else {
                continue
            }
            let runRange = NSRange(
                location: runCFRange.location,
                length: runCFRange.length
            )
            let visibleCandidateRange = NSIntersectionRange(runRange, sourceRange)
            guard visibleCandidateRange.length > 0,
                  containsVisibleCharacter(in: string, range: visibleCandidateRange) else {
                continue
            }

            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            func isVisibleEvidence(glyph: CGGlyph, stringIndex: CFIndex) -> Bool {
                guard glyph != 0,
                      stringIndex != kCFNotFound,
                      stringIndex >= 0,
                      stringIndex < string.length,
                      NSLocationInRange(stringIndex, visibleCandidateRange) else {
                    return false
                }
                return isVisibleUTF16CodeUnit(in: string, at: stringIndex)
            }

            if let glyphs = CTRunGetGlyphsPtr(run),
               let stringIndices = CTRunGetStringIndicesPtr(run) {
                for index in 0..<glyphCount where isVisibleEvidence(
                    glyph: glyphs[index],
                    stringIndex: stringIndices[index]
                ) {
                    return true
                }
                continue
            }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var stringIndices = [CFIndex](repeating: kCFNotFound, count: glyphCount)
            let fullRunRange = CFRange(location: 0, length: 0)
            glyphs.withUnsafeMutableBufferPointer { buffer in
                CTRunGetGlyphs(run, fullRunRange, buffer.baseAddress!)
            }
            stringIndices.withUnsafeMutableBufferPointer { buffer in
                CTRunGetStringIndices(run, fullRunRange, buffer.baseAddress!)
            }
            for index in 0..<glyphCount where isVisibleEvidence(
                glyph: glyphs[index],
                stringIndex: stringIndices[index]
            ) {
                return true
            }
        }

        return false
    }

    private static func shapedMeasurement(
        for text: String,
        ctFont: CTFont,
        baseFontLineMetrics: RawFontLineMetrics
    ) -> CachedSegmentMeasurement {
        let source = text as NSString
        let sourceRange = NSRange(location: 0, length: source.length)
        let containsVisibleCharacter = containsVisibleCharacter(
            in: source,
            range: sourceRange
        )
        return CoreTextLayoutSafetyGate.withLock {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: attributes)
            )
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            var metrics: [RawFontLineMetrics] = []
            metrics.reserveCapacity(min(max(runs.count, 1), 3))

            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName] as! CTFont
                // TextKit excludes the requested font's line box when every
                // glyph is supplied by fallback fonts. Use its platform-specific
                // baseline only when CoreText retained that font for this run.
                let usesRequestedFont = CFEqual(runFont, ctFont)
                let runMetrics = usesRequestedFont
                    ? baseFontLineMetrics
                    : rawLineMetrics(for: runFont)
                if !metrics.contains(runMetrics) {
                    metrics.append(runMetrics)
                }
            }

            // A nonempty shaped segment normally has at least one run. Retain a
            // safe line box for control-only input if CoreText emits none.
            if metrics.isEmpty {
                metrics.append(baseFontLineMetrics)
            }

            return CachedSegmentMeasurement(
                width: width,
                fontMetrics: FontLineMetricSet(metrics),
                containsRequestedFontRun: requestedFontSuppliesVisibleGlyph(
                    in: line,
                    string: source,
                    requestedFont: ctFont,
                    sourceRange: sourceRange
                ),
                containsVisibleCharacter: containsVisibleCharacter
            )
        }
    }

    private static func baseFontLineMetrics(
        for font: Font,
        ctFont: CTFont
    ) -> RawFontLineMetrics {
        #if canImport(UIKit)
        return rawLineMetrics(for: ctFont)
        #elseif canImport(AppKit)
        // AppKit's TextKit 1 baseline is not derivable from CTFont ascent for
        // every NSFont. Helvetica/Courier, for example, add a three-point top
        // allowance. Preserve the renderer's baseline while fallback runs keep
        // using their CoreText metrics below.
        return RawFontLineMetrics(
            ascent: defaultLineMetrics(for: font).baselineOffset,
            descent: CTFontGetDescent(ctFont).rounded(),
            leading: max(CTFontGetLeading(ctFont), 0)
        )
        #endif
    }

    private static func rawLineMetrics(for font: CTFont) -> RawFontLineMetrics {
        #if canImport(UIKit)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        #elseif canImport(AppKit)
        // AppKit TextKit 1 quantizes the baseline-side font metrics to whole
        // points before applying `lineHeightMultiple`; UIKit preserves the raw
        // CoreText values. The platform-specific oracle matrix locks both paths.
        let ascent = CTFontGetAscent(font).rounded()
        let descent = CTFontGetDescent(font).rounded()
        #endif
        return RawFontLineMetrics(
            ascent: ascent,
            descent: descent,
            leading: max(CTFontGetLeading(font), 0)
        )
    }

    private static func widthCacheKey(for text: String, fontKey: FontCacheKey) -> WidthCache.Key {
        WidthCache.Key(
            fontName: fontKey.fontName,
            pointSizeMilli: fontKey.pointSizeMilli,
            text: text
        )
    }

    private static func discretionaryHyphenMeasurement(
        preparedText: ArithmeticTextCalculator.PreparedText,
        runStartSegmentIndex: Int,
        ctFont: CTFont,
        fontKey: FontCacheKey,
        baseFontLineMetrics: RawFontLineMetrics,
        preparationCache: PreparationCache
    ) -> DiscretionaryHyphenMeasurement {
        let hyphen = "-"
        let fallbackMeasurement = preparationCache.segmentMeasurement(
            for: widthCacheKey(for: hyphen, fontKey: fontKey),
            text: hyphen,
            ctFont: ctFont,
            baseFontLineMetrics: baseFontLineMetrics
        )
        let fallback = DiscretionaryHyphenMeasurement(
            advance: fallbackMeasurement.width,
            containsRequestedFontRun: fallbackMeasurement.containsRequestedFontRun ?? false
        )
        guard let precedingIndex = preparedText.widths.indices.last,
              precedingIndex >= runStartSegmentIndex,
              preparedText.kinds[precedingIndex] == .text,
              !preparedText.segmentTexts[precedingIndex].isEmpty else {
            return fallback
        }

        let shapedText = preparedText.segmentTexts[precedingIndex] + hyphen
        let shapedNSString = shapedText as NSString
        let hyphenLocation = shapedNSString.length - 1
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ]
        let shaped = CoreTextLayoutSafetyGate.withLock {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: shapedText, attributes: attributes)
            )
            return (
                width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)),
                containsRequestedFontRun: requestedFontSuppliesVisibleGlyph(
                    in: line,
                    string: shapedNSString,
                    requestedFont: ctFont,
                    sourceRange: NSRange(location: hyphenLocation, length: 1)
                )
            )
        }
        return DiscretionaryHyphenMeasurement(
            advance: max(0, shaped.width - preparedText.widths[precedingIndex]),
            containsRequestedFontRun: shaped.containsRequestedFontRun
        )
    }

    /// Preserve descriptor-backed platform fonts so private system names never
    /// substitute a different face. AppKit's direct bridge also avoids creating
    /// a detached CTFont proxy that can perturb TextKit's process default font.
    private static func ctFont(from font: Font) -> CTFont {
        #if canImport(AppKit)
        return font as CTFont
        #elseif canImport(UIKit)
        CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, font.pointSize, nil)
        #endif
    }
}
