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

    static func prepare(attributedString: NSAttributedString) -> ArithmeticTextCalculator.PreparedText {
        var preparedText = ArithmeticTextCalculator.PreparedText()
        let fullString = attributedString.string
        let fullNSString = fullString as NSString
        let utf16Characters = Array(fullString.utf16)
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var capturedParagraphStyle = false

        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            guard let font = attributes[.font] as? Font else { return }
            prepareRun(
                attributes: attributes,
                range: range,
                fullString: fullNSString,
                utf16: utf16Characters,
                font: font,
                preparedText: &preparedText,
                capturedParagraphStyle: &capturedParagraphStyle
            )
        }

        return preparedText
    }

    private static func prepareRun(
        attributes: [NSAttributedString.Key: Any],
        range: NSRange,
        fullString: NSString,
        utf16: [unichar],
        font: Font,
        preparedText: inout ArithmeticTextCalculator.PreparedText,
        capturedParagraphStyle: inout Bool
    ) {
        let fontCacheKey = FontCacheKey(
            fontName: font.fontName,
            pointSizeMilli: Int((font.pointSize * 1000).rounded())
        )
        let ctFont = ctFont(from: font)
        #if canImport(UIKit)
        let lineHeightMetric = font.lineHeight
        #elseif canImport(AppKit)
        let lineHeightMetric = font.ascender - font.descender + font.leading
        #endif
        var lineHeight = lineHeightMetric

        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            let multiplier = paragraphStyle.lineHeightMultiple
            if multiplier > 0 {
                lineHeight *= multiplier
            }

            if !capturedParagraphStyle {
                preparedText.headIndent = paragraphStyle.headIndent
                preparedText.firstLineHeadIndent = paragraphStyle.firstLineHeadIndent
                capturedParagraphStyle = true
            }
        }

        let discretionaryHyphenWidth = measureTextWidth("-", ctFont: ctFont, fontKey: fontCacheKey)
        var glyphs = [CGGlyph](repeating: 0, count: range.length)
        var advances = [CGSize](repeating: .zero, count: range.length)
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
                    glyphs: &glyphs,
                    advances: &advances,
                    preparedText: &preparedText
                )
            case .softHyphen:
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

    private static func appendMeasuredSegment(
        range: NSRange,
        kind: ArithmeticTextCalculator.SegmentKind,
        fullString: NSString,
        utf16: [unichar],
        ctFont: CTFont,
        fontKey: FontCacheKey,
        lineHeight: CGFloat,
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
