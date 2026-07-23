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

    private struct FontCacheKey: Hashable {
        let fontName: String
        let pointSizeMilli: Int
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
        private var storage: [Key: CGFloat] = [:]
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
            return storage[key]
        }

        /// Stores `width` for `key`. A non-positive `capacity` retains nothing.
        /// Updating an existing key overwrites its value in place without
        /// consuming a ring slot or altering eviction order. A new key is
        /// appended while the ring is still filling; once full, it evicts the
        /// oldest surviving key at `writeIndex`.
        func insert(_ width: CGFloat, for key: Key) {
            guard capacity > 0 else { return }
            lock.lock()
            defer { lock.unlock() }
            if storage.updateValue(width, forKey: key) != nil {
                return
            }
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
    #if canImport(AppKit)
    private static let cachedDefaultLineHeights = DefaultLineHeightCache(capacity: 256)
    #endif

    static func prepare(attributedString: NSAttributedString) -> ArithmeticTextCalculator.PreparedText {
        var preparedText = ArithmeticTextCalculator.PreparedText()
        let fullString = attributedString.string
        let fullNSString = fullString as NSString
        let utf16Characters = Array(fullString.utf16)

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
                preparedText: &preparedText
            )
            return preparedText
        }

        prepareParagraphs(
            in: fullNSString,
            attributedString: attributedString,
            utf16: utf16Characters,
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
                        )
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
                    preparedText: &preparedText
                )
            }
        }

        let metrics = resolvedMetrics ?? paragraphMetrics(for: paragraph, in: attributedString)

        if let separatorRange = paragraph.separatorRange {
            let separatorAttributes = attributedString.attributes(at: separatorRange.location, effectiveRange: nil)
            let separatorFont = font(from: separatorAttributes)
            preparedText.append(
                width: 0,
                kind: .hardBreak,
                height: layoutLineHeight(
                    for: separatorFont,
                    lineHeightMultiple: metrics.lineHeightMultiple
                )
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
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        let font = font(from: attributes)
        let fontCacheKey = fontCacheKey(for: font)
        let ctFont = ctFont(from: font)
        let lineHeight = cachedLineHeight
            ?? layoutLineHeight(
                for: font,
                lineHeightMultiple: paragraphLineHeightMultiple
            )

        let runStartSegmentIndex = preparedText.widths.count
        var glyphs: [CGGlyph] = []
        var advances: [CGSize] = []
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
                        utf16: utf16,
                        ctFont: ctFont,
                        fontKey: fontCacheKey,
                        lineHeight: lineHeight,
                        scratchCapacity: range.length,
                        glyphs: &glyphs,
                        advances: &advances,
                        preparedText: &preparedText
                    )
                }
            case .space:
                appendMeasuredSegment(
                    range: span.range,
                    kind: .space,
                    fullString: fullString,
                    utf16: utf16,
                    ctFont: ctFont,
                    fontKey: fontCacheKey,
                    lineHeight: lineHeight,
                    scratchCapacity: range.length,
                    glyphs: &glyphs,
                    advances: &advances,
                    preparedText: &preparedText
                )
            case .softHyphen:
                let discretionaryHyphenWidth = discretionaryHyphenAdvance(
                    preparedText: preparedText,
                    runStartSegmentIndex: runStartSegmentIndex,
                    ctFont: ctFont,
                    fontKey: fontCacheKey
                )
                preparedText.append(
                    width: 0,
                    kind: .softHyphen,
                    height: lineHeight,
                    lineEndFitAdvance: discretionaryHyphenWidth,
                    lineEndPaintAdvance: discretionaryHyphenWidth
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
                preparedText: &preparedText
            )
        }
    }

    private static func paragraphMetrics(
        for paragraph: ParagraphUTF16Range,
        in attributedString: NSAttributedString
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
            fontAttributes: fontAttributes
        )
    }

    private static func paragraphMetrics(
        for paragraph: ParagraphUTF16Range,
        styleAttributes: [NSAttributedString.Key: Any],
        fontAttributes: [NSAttributedString.Key: Any]
    ) -> ParagraphMetrics {
        let paragraphStyle = styleAttributes[.paragraphStyle] as? NSParagraphStyle
        let lineHeightMultiple = effectiveLineHeightMultiple(from: paragraphStyle)
        let emptyLineFont = font(from: fontAttributes)

        return ParagraphMetrics(
            firstLineHeadIndent: nonnegativeFiniteMetric(paragraphStyle?.firstLineHeadIndent),
            headIndent: nonnegativeFiniteMetric(paragraphStyle?.headIndent),
            paragraphSpacingBefore: nonnegativeFiniteMetric(paragraphStyle?.paragraphSpacingBefore),
            paragraphSpacingAfter: paragraph.separatorRange == nil
                ? 0
                : nonnegativeFiniteMetric(paragraphStyle?.paragraphSpacing),
            lineHeightMultiple: lineHeightMultiple,
            emptyLineHeight: layoutLineHeight(
                for: emptyLineFont,
                lineHeightMultiple: lineHeightMultiple
            )
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
        (attributes[.font] as? Font) ?? Font.systemFont(ofSize: Font.systemFontSize)
    }

    private static func fontCacheKey(for font: Font) -> FontCacheKey {
        FontCacheKey(
            fontName: font.fontName,
            pointSizeMilli: Int((font.pointSize * 1000).rounded())
        )
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
    private final class DefaultLineHeightCache: @unchecked Sendable {
        private let capacity: Int
        private let lock = NSLock()
        private var storage: [Font: CGFloat] = [:]
        private var ring: [Font] = []
        private var writeIndex = 0

        init(capacity: Int) {
            self.capacity = max(0, capacity)
        }

        func value(for font: Font) -> CGFloat {
            lock.lock()
            if let cachedHeight = storage[font] {
                lock.unlock()
                return cachedHeight
            }
            lock.unlock()

            let measuredHeight = NSLayoutManager().defaultLineHeight(for: font)
            guard capacity > 0 else { return measuredHeight }

            lock.lock()
            defer { lock.unlock() }
            if let cachedHeight = storage[font] {
                return cachedHeight
            }
            if ring.count < capacity {
                ring.append(font)
            } else {
                storage.removeValue(forKey: ring[writeIndex])
                ring[writeIndex] = font
                writeIndex = (writeIndex + 1) % capacity
            }
            storage[font] = measuredHeight
            return measuredHeight
        }
    }

    private static func defaultLineHeight(for font: Font) -> CGFloat {
        cachedDefaultLineHeights.value(for: font)
    }
    #endif

    private static func appendMeasuredSegment(
        range: NSRange,
        kind: ArithmeticTextCalculator.SegmentKind,
        fullString: NSString,
        utf16: [unichar],
        ctFont: CTFont,
        fontKey: FontCacheKey,
        lineHeight: CGFloat,
        scratchCapacity: Int,
        glyphs: inout [CGGlyph],
        advances: inout [CGSize],
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        guard range.length > 0 else { return }

        let segmentText = fullString.substring(with: range)
        if let cachedWidth = cachedWidth(for: segmentText, fontKey: fontKey) {
            append(
                width: cachedWidth,
                kind: kind,
                text: segmentText,
                ctFont: ctFont,
                lineHeight: lineHeight,
                preparedText: &preparedText
            )
            return
        }

        if glyphs.isEmpty {
            glyphs = [CGGlyph](repeating: 0, count: scratchCapacity)
            advances = [CGSize](repeating: .zero, count: scratchCapacity)
        }

        utf16.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let characters = baseAddress.advanced(by: range.location)
            let hasGlyphs = CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, range.length)

            if hasGlyphs {
                CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, range.length)
                var width: CGFloat = 0
                for index in 0..<range.length {
                    width += advances[index].width
                }
                storeCachedWidth(width, for: segmentText, fontKey: fontKey)
                append(
                    width: width,
                    kind: kind,
                    text: segmentText,
                    ctFont: ctFont,
                    lineHeight: lineHeight,
                    preparedText: &preparedText
                )
            } else {
                storeCachedWidth(0, for: segmentText, fontKey: fontKey)
                append(
                    width: 0,
                    kind: kind,
                    text: segmentText,
                    ctFont: ctFont,
                    lineHeight: lineHeight,
                    preparedText: &preparedText
                )
            }
        }
    }

    private static func append(
        width: CGFloat,
        kind: ArithmeticTextCalculator.SegmentKind,
        text: String,
        ctFont: CTFont,
        lineHeight: CGFloat,
        preparedText: inout ArithmeticTextCalculator.PreparedText
    ) {
        preparedText.append(
            width: width,
            kind: kind,
            height: lineHeight,
            text: kind == .text ? text : "",
            ctFont: kind == .text ? ctFont : nil
        )
    }

    private static func cachedWidth(for text: String, fontKey: FontCacheKey) -> CGFloat? {
        let key = WidthCache.Key(
            fontName: fontKey.fontName,
            pointSizeMilli: fontKey.pointSizeMilli,
            text: text
        )
        return cachedWidths.value(for: key)
    }

    private static func storeCachedWidth(_ width: CGFloat, for text: String, fontKey: FontCacheKey) {
        let key = WidthCache.Key(
            fontName: fontKey.fontName,
            pointSizeMilli: fontKey.pointSizeMilli,
            text: text
        )
        cachedWidths.insert(width, for: key)
    }

    private static func discretionaryHyphenAdvance(
        preparedText: ArithmeticTextCalculator.PreparedText,
        runStartSegmentIndex: Int,
        ctFont: CTFont,
        fontKey: FontCacheKey
    ) -> CGFloat {
        let fallbackWidth = measureTextWidth("-", ctFont: ctFont, fontKey: fontKey)
        guard let precedingIndex = preparedText.widths.indices.last,
              precedingIndex >= runStartSegmentIndex,
              preparedText.kinds[precedingIndex] == .text,
              !preparedText.segmentTexts[precedingIndex].isEmpty else {
            return fallbackWidth
        }

        let shapedText = preparedText.segmentTexts[precedingIndex] + "-"
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: shapedText, attributes: attributes)
        )
        let shapedWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return max(0, shapedWidth - preparedText.widths[precedingIndex])
    }

    private static func measureTextWidth(_ text: String, ctFont: CTFont, fontKey: FontCacheKey) -> CGFloat {
        if let cachedWidth = cachedWidth(for: text, fontKey: fontKey) {
            return cachedWidth
        }

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        storeCachedWidth(width, for: text, fontKey: fontKey)
        return width
    }

    /// Reconstruct from the platform descriptor so private system font names never substitute a different font.
    private static func ctFont(from font: Font) -> CTFont {
        CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, font.pointSize, nil)
    }
}
