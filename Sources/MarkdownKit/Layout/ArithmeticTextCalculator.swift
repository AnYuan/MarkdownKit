//
//  ArithmeticTextCalculator.swift
//  MarkdownKit
//

import Foundation
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A high-performance, lock-free text calculator that calculates the bounding
/// sizes of `NSAttributedString` blocks using pure arithmetic and CoreText
/// width measurements.
///
/// This calculator is heavily inspired by `@chenglou/pretext`.
/// It avoids the massive overhead of instantiating `NSTextStorage` and `NSLayoutManager`
/// by caching word/grapheme widths and mathematically computing line breaks.
///
/// - Important: This class should only be used for pure-text nodes that do
///   NOT contain inline attachments (e.g. math formulas, images) or
///   complex text shaping requirements (e.g. Arabic, Thai ligatures).
public final class ArithmeticTextCalculator {

    struct PreparedTextProfile {
        var containsUnsupportedScript = false
        var containsAttachment = false

        var supportsArithmeticLayout: Bool {
            !containsUnsupportedScript && !containsAttachment
        }
    }

    private struct PreparedTextRunKey: Hashable {
        let location: Int
        let length: Int
        let fontName: String
        let pointSizeMilli: Int
        let lineHeightMultipleMilli: Int
        let headIndentMilli: Int
        let firstLineHeadIndentMilli: Int
    }

    private struct PreparedTextCacheKey: Hashable {
        let string: String
        let localeIdentifier: String
        let runs: [PreparedTextRunKey]
    }

    private struct FontCacheKey: Hashable {
        let fontName: String
        let pointSizeMilli: Int

        var nsCacheKey: NSString {
            "\(fontName)|\(pointSizeMilli)" as NSString
        }
    }

    /// NSObject wrapper around `PreparedTextCacheKey` so it can be used as `NSCache` key.
    private final class PreparedTextCacheKeyObject: NSObject {
        let value: PreparedTextCacheKey
        init(_ value: PreparedTextCacheKey) { self.value = value }

        override var hash: Int { value.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            (object as? PreparedTextCacheKeyObject)?.value == value
        }
    }

    /// Class wrapper because `NSCache` requires class values; `PreparedText` is a struct.
    private final class PreparedTextWrapper {
        let value: PreparedText
        init(_ value: PreparedText) { self.value = value }
    }

    /// NSCache is internally thread-safe; soft `countLimit` prevents unbounded growth.
    /// Plain `Dictionary` previously leaked memory in long-running apps that processed
    /// many distinct font/text combinations.
    /// `nonisolated(unsafe)` is appropriate: NSCache documents its API as thread-safe,
    /// but it does not formally conform to `Sendable`.
    private static nonisolated(unsafe) let cachedWidths: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 50_000
        return cache
    }()

    private static nonisolated(unsafe) let cachedPreparedTexts: NSCache<PreparedTextCacheKeyObject, PreparedTextWrapper> = {
        let cache = NSCache<PreparedTextCacheKeyObject, PreparedTextWrapper>()
        cache.countLimit = 1_024
        return cache
    }()

    // MARK: - Test diagnostics (do not use in production paths)
    private static let testCounterLock = NSLock()
    private static nonisolated(unsafe) var preparedTextCacheHits: Int = 0
    private static nonisolated(unsafe) var preparedTextCacheMisses: Int = 0

    enum SegmentKind {
        case text
        case space
        case softHyphen
        case hardBreak

        var isSpace: Bool {
            self == .space
        }

        var isHardBreak: Bool {
            self == .hardBreak
        }

        func lineEndFitAdvance(for width: CGFloat) -> CGFloat {
            switch self {
            case .text:
                return width
            case .space, .softHyphen, .hardBreak:
                return 0
            }
        }

        func lineEndPaintAdvance(for width: CGFloat) -> CGFloat {
            switch self {
            case .text, .space:
                return width
            case .softHyphen, .hardBreak:
                return 0
            }
        }
    }

    enum ChunkKind {
        case content
        case hardBreak
    }

    struct Chunk {
        let kind: ChunkKind
        let segmentIndex: Int
    }

    /// Structure of Arrays (SoA) representing the segmented text for extremely fast iteration.
    struct PreparedText {
        var widths: [CGFloat] = []
        var kinds: [SegmentKind] = []
        var lineEndFitAdvances: [CGFloat] = []
        var lineEndPaintAdvances: [CGFloat] = []
        var segmentTexts: [String] = []
        // Stores the concrete `CTFont` captured during preparation (for `.text`
        // segments only) so oversized-token fallback can reuse the exact font
        // instance instead of reconstructing one from a string name. Re-deriving
        // a `CTFont` from `Font.fontName` breaks on iOS, where system fonts
        // report a private PostScript name (e.g. ".SFUI-Regular") that
        // `CTFontCreateWithName` cannot resolve, silently substituting Times.
        var ctFonts: [CTFont?] = []
        var heights: [CGFloat] = []
        var chunks: [Chunk] = []
        var headIndent: CGFloat = 0
        var firstLineHeadIndent: CGFloat = 0
        
        mutating func append(
            width: CGFloat,
            kind: SegmentKind,
            height: CGFloat,
            text: String = "",
            ctFont: CTFont? = nil,
            lineEndFitAdvance: CGFloat? = nil,
            lineEndPaintAdvance: CGFloat? = nil
        ) {
            self.widths.append(width)
            self.kinds.append(kind)
            self.lineEndFitAdvances.append(lineEndFitAdvance ?? kind.lineEndFitAdvance(for: width))
            self.lineEndPaintAdvances.append(lineEndPaintAdvance ?? kind.lineEndPaintAdvance(for: width))
            self.segmentTexts.append(text)
            self.ctFonts.append(ctFont)
            self.heights.append(height)
            self.chunks.append(
                Chunk(
                    kind: kind.isHardBreak ? .hardBreak : .content,
                    segmentIndex: self.widths.count - 1
                )
            )
        }
    }

    public init() {}

    static func preparedTextCacheHitsForTesting() -> Int {
        testCounterLock.lock()
        defer { testCounterLock.unlock() }
        return preparedTextCacheHits
    }

    static func preparedTextCacheMissesForTesting() -> Int {
        testCounterLock.lock()
        defer { testCounterLock.unlock() }
        return preparedTextCacheMisses
    }

    static func resetPreparedTextCacheForTesting() {
        cachedPreparedTexts.removeAllObjects()
        testCounterLock.lock()
        preparedTextCacheHits = 0
        preparedTextCacheMisses = 0
        testCounterLock.unlock()
    }

    func profile(for attributedString: NSAttributedString) -> PreparedTextProfile {
        guard attributedString.length > 0 else { return PreparedTextProfile() }

        var profile = PreparedTextProfile()
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, _, stop in
            if value != nil {
                profile.containsAttachment = true
                stop.pointee = true
            }
        }

        if profile.containsAttachment {
            return profile
        }

        for scalar in attributedString.string.unicodeScalars where Self.requiresTextKitFallback(for: scalar) {
            profile.containsUnsupportedScript = true
            break
        }

        return profile
    }

    private static func cachedWidth(for text: String, fontKey: FontCacheKey) -> CGFloat? {
        let key = "\(fontKey.fontName)|\(fontKey.pointSizeMilli)|\(text)" as NSString
        return cachedWidths.object(forKey: key).map { CGFloat(truncating: $0) }
    }

    private static func cachedPreparedText(for key: PreparedTextCacheKey) -> PreparedText? {
        let keyObject = PreparedTextCacheKeyObject(key)
        if let wrapper = cachedPreparedTexts.object(forKey: keyObject) {
            testCounterLock.lock()
            preparedTextCacheHits += 1
            testCounterLock.unlock()
            return wrapper.value
        }
        testCounterLock.lock()
        preparedTextCacheMisses += 1
        testCounterLock.unlock()
        return nil
    }

    private static func storeCachedWidth(_ width: CGFloat, for text: String, fontKey: FontCacheKey) {
        let key = "\(fontKey.fontName)|\(fontKey.pointSizeMilli)|\(text)" as NSString
        cachedWidths.setObject(NSNumber(value: Double(width)), forKey: key)
    }

    private static func storePreparedText(_ preparedText: PreparedText, for key: PreparedTextCacheKey) {
        let keyObject = PreparedTextCacheKeyObject(key)
        cachedPreparedTexts.setObject(PreparedTextWrapper(preparedText), forKey: keyObject)
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

    /// Derives a `CTFont` from the platform `Font`'s own descriptor rather than
    /// re-opening `font.fontName` as a PostScript name via `CTFontCreateWithName`.
    /// `UIFontDescriptor`/`NSFontDescriptor` are toll-free bridged to
    /// `CTFontDescriptor`, so this reconstructs the exact font CoreText would
    /// resolve for TextKit, including private system font identities (e.g. iOS
    /// system fonts, whose `fontName` is a private name such as ".SFUI-Regular"
    /// that `CTFontCreateWithName` cannot look up and silently falls back to
    /// Times for).
    private static func ctFont(from font: Font) -> CTFont {
        CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, font.pointSize, nil)
    }

    private static func requiresTextKitFallback(for scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF,
             0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF,
             0x0900...0x0D7F, 0x0E00...0x0E7F, 0x1000...0x109F,
             0x1780...0x17FF:
            return true
        default:
            return false
        }
    }

    /// Calculates the exact bounding size for a given attributed string constrained to a width.
    ///
    /// - Parameters:
    ///   - attributedString: The pure-text themed string to measure.
    ///   - maxWidth: The maximum width of the containing viewport.
    /// - Returns: The precise `CGSize` necessary to display the text without clipping.
    public func calculateSize(for attributedString: NSAttributedString, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        let preparedText = prepare(attributedString: attributedString)
        return layout(prepared: preparedText, constrainedToWidth: maxWidth)
    }

    /// Prepares a pure-text attributed string into a width-independent structure-of-arrays payload.
    func prepare(attributedString: NSAttributedString) -> PreparedText {
        guard attributedString.length > 0 else { return PreparedText() }
        let cacheKey = preparedTextCacheKey(for: attributedString)
        if let cachedPreparedText = Self.cachedPreparedText(for: cacheKey) {
            return cachedPreparedText
        }

        let preparedText = buildPreparedText(from: attributedString)
        Self.storePreparedText(preparedText, for: cacheKey)
        return preparedText
    }

    /// Lays out a previously prepared payload at a specific width using pure arithmetic.
    func layout(prepared preparedText: PreparedText, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        guard !preparedText.widths.isEmpty else { return .zero }

        var currentLineAdvance: CGFloat = 0
        var currentLineFitWidth: CGFloat = 0
        var currentLinePaintWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxComputedWidth: CGFloat = 0
        var lineCount = 0

        func committedLinePaintWidth(availableWidth: CGFloat) -> CGFloat {
            guard currentLinePaintWidth > currentLineFitWidth else {
                return currentLinePaintWidth
            }

            // TextKit retains trailing separator advance while it fits, but its
            // used rect stops at the line-fragment boundary when it overhangs.
            return min(currentLinePaintWidth, max(availableWidth, currentLineFitWidth))
        }

        func appendOversizedTextSegment(
            text: String,
            ctFont: CTFont,
            height: CGFloat
        ) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
            let nsText = text as NSString
            var start = 0

            while start < nsText.length {
                let currentIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
                let availableWidth = max(maxWidth - currentIndent, 0)
                var count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(availableWidth))

                if count <= 0 {
                    count = nsText.rangeOfComposedCharacterSequence(at: start).length
                }

                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

                currentLineAdvance = lineWidth
                currentLineFitWidth = lineWidth
                currentLinePaintWidth = lineWidth
                currentLineHeight = max(currentLineHeight, height)
                start += count

                if start < nsText.length {
                    totalHeight += currentLineHeight
                    maxComputedWidth = max(maxComputedWidth, currentLinePaintWidth + currentIndent)
                    lineCount += 1
                    currentLineAdvance = 0
                    currentLineFitWidth = 0
                    currentLinePaintWidth = 0
                    currentLineHeight = 0
                }
            }
        }

        for chunk in preparedText.chunks {
            let index = chunk.segmentIndex
            let width = preparedText.widths[index]
            let lineEndFitAdvance = preparedText.lineEndFitAdvances[index]
            let lineEndPaintAdvance = preparedText.lineEndPaintAdvances[index]
            let segmentText = preparedText.segmentTexts[index]
            let ctFont = preparedText.ctFonts[index]
            let kind = preparedText.kinds[index]
            let height = preparedText.heights[index]
            let currentIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
            let availableWidth = maxWidth - currentIndent
            
            if chunk.kind == .hardBreak {
                totalHeight += max(currentLineHeight, height)
                let committedPaintWidth = committedLinePaintWidth(availableWidth: availableWidth)
                let visibleLineWidth = committedPaintWidth > 0 ? committedPaintWidth + currentIndent : 0
                maxComputedWidth = max(maxComputedWidth, visibleLineWidth)
                currentLineAdvance = 0
                currentLineFitWidth = 0
                currentLinePaintWidth = 0
                currentLineHeight = 0
                lineCount += 1
                continue
            }

            let nextLineAdvance = currentLineAdvance + width
            let nextLineFitWidth = currentLineAdvance + lineEndFitAdvance
            let nextLinePaintWidth = currentLineAdvance + lineEndPaintAdvance

            if nextLineFitWidth > availableWidth && currentLineAdvance > 0 {
                // Break line
                totalHeight += currentLineHeight
                let committedPaintWidth = committedLinePaintWidth(availableWidth: availableWidth)
                maxComputedWidth = max(maxComputedWidth, committedPaintWidth + currentIndent)
                
                lineCount += 1
                if kind.isSpace {
                    currentLineAdvance = 0
                    currentLineFitWidth = 0
                    currentLinePaintWidth = 0
                    currentLineHeight = 0
                } else {
                    let nextIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
                    let nextAvailableWidth = maxWidth - nextIndent
                    if let ctFont, kind == .text && width > nextAvailableWidth && !segmentText.isEmpty {
                        currentLineAdvance = 0
                        currentLineFitWidth = 0
                        currentLinePaintWidth = 0
                        currentLineHeight = 0
                        appendOversizedTextSegment(
                            text: segmentText,
                            ctFont: ctFont,
                            height: height
                        )
                    } else {
                        currentLineAdvance = width
                        currentLineFitWidth = lineEndFitAdvance
                        currentLinePaintWidth = lineEndPaintAdvance
                        currentLineHeight = height
                    }
                }
            } else if let ctFont, nextLineFitWidth > availableWidth && kind == .text && !segmentText.isEmpty {
                appendOversizedTextSegment(
                    text: segmentText,
                    ctFont: ctFont,
                    height: height
                )
            } else {
                currentLineAdvance = nextLineAdvance
                currentLineFitWidth = nextLineFitWidth
                currentLinePaintWidth = nextLinePaintWidth
                currentLineHeight = max(currentLineHeight, height)
            }
        }
        
        // Add final line height if it wasn't empty
        if currentLineAdvance > 0 || totalHeight == 0 {
            let currentIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
            let availableWidth = maxWidth - currentIndent
            totalHeight += currentLineHeight
            let committedPaintWidth = committedLinePaintWidth(availableWidth: availableWidth)
            let visibleLineWidth = committedPaintWidth > 0 ? committedPaintWidth + currentIndent : 0
            maxComputedWidth = max(maxComputedWidth, visibleLineWidth)
        }
        
        return CGSize(width: ceil(maxComputedWidth), height: floor(totalHeight))
    }

    /// Segments the attributed string into words and whitespace, measuring the exact width
    /// of each segment using CoreText, and returning a Structure of Arrays (SoA) payload.
    private func buildPreparedText(from attributedString: NSAttributedString) -> PreparedText {
        var preparedText = PreparedText()
        let fullString = attributedString.string
        let fullNSString = fullString as NSString
        let utf16Chars = Array(fullString.utf16) // Single allocation of the entire text buffer
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var capturedParagraphStyle = false
        
        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            guard let font = attributes[.font] as? Font else { return }
            let fontCacheKey = FontCacheKey(
                fontName: font.fontName,
                pointSizeMilli: Int((font.pointSize * 1000).rounded())
            )
            
            // Convert platform Font to CTFont via the font's own descriptor, never
            // by re-opening `font.fontName` as a PostScript name. System fonts
            // (e.g. `UIFont.systemFont(ofSize:)`) report a private name on iOS
            // (".SFUI-Regular") that `CTFontCreateWithName` cannot resolve back
            // to the original font, silently substituting Times and diverging
            // from TextKit's metrics, which measure the original font object.
            let ctFont = Self.ctFont(from: font)
            #if canImport(UIKit)
            let lineHeightMetric = font.lineHeight
            #elseif canImport(AppKit)
            let lineHeightMetric = font.ascender - font.descender + font.leading
            #endif
            
            // Approximate line height based on font metrics
            var lineHeight = lineHeightMetric
            
            // Adjust line height multiplier if specified in paragraph style
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

            let discretionaryHyphenWidth = Self.measureTextWidth("-", ctFont: ctFont, fontKey: fontCacheKey)
            
            // Reusable buffers for this font range to avoid allocating per-word
            var glyphs = [CGGlyph](repeating: 0, count: range.length)
            var advances = [CGSize](repeating: .zero, count: range.length)
            
            var segmentStartIndex = range.location
            var isCurrentSpace = false
            
            // Inline helper to measure a chunk without allocations
            func measureSegment(from start: Int, to end: Int, kind: SegmentKind, terminatesWithHardBreak: Bool) {
                let count = end - start
                guard count > 0 else {
                    if terminatesWithHardBreak {
                        preparedText.append(width: 0, kind: .hardBreak, height: lineHeight)
                    }
                    return
                }

                let segmentText = fullNSString.substring(with: NSRange(location: start, length: count))
                if let cachedWidth = Self.cachedWidth(for: segmentText, fontKey: fontCacheKey) {
                    preparedText.append(
                        width: cachedWidth,
                        kind: kind,
                        height: lineHeight,
                        text: kind == .text ? segmentText : "",
                        ctFont: kind == .text ? ctFont : nil
                    )
                    if terminatesWithHardBreak {
                        preparedText.append(width: 0, kind: .hardBreak, height: lineHeight)
                    }
                    return
                }
                
                utf16Chars.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return }
                    let ptr = baseAddress.advanced(by: start)
                    
                    let hasGlyphs = CTFontGetGlyphsForCharacters(ctFont, ptr, &glyphs, count)
                    if hasGlyphs {
                        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, count)
                        
                        var width: CGFloat = 0
                        for i in 0..<count { width += advances[i].width }
                        Self.storeCachedWidth(width, for: segmentText, fontKey: fontCacheKey)
                        preparedText.append(
                            width: width,
                            kind: kind,
                            height: lineHeight,
                            text: kind == .text ? segmentText : "",
                            ctFont: kind == .text ? ctFont : nil
                        )
                    } else {
                        Self.storeCachedWidth(0, for: segmentText, fontKey: fontCacheKey)
                        preparedText.append(
                            width: 0,
                            kind: kind,
                            height: lineHeight,
                            text: kind == .text ? segmentText : "",
                            ctFont: kind == .text ? ctFont : nil
                        )
                    }
                }
                
                if terminatesWithHardBreak {
                    preparedText.append(width: 0, kind: .hardBreak, height: lineHeight)
                }
            }

            func isGlueCharacter(_ char: unichar) -> Bool {
                char == 0x00A0 || char == 0x202F || char == 0x2060
            }

            func measureLocalizedTextRange(from start: Int, to end: Int) {
                let textRange = NSRange(location: start, length: end - start)
                guard textRange.length > 0 else { return }

                var wordRanges: [NSRange] = []
                fullNSString.enumerateSubstrings(
                    in: textRange,
                    options: [.byWords, .substringNotRequired, .localized]
                ) { _, substringRange, _, _ in
                    let clampedRange = NSIntersectionRange(textRange, substringRange)
                    if clampedRange.length > 0 {
                        wordRanges.append(clampedRange)
                    }
                }

                guard !wordRanges.isEmpty else {
                    measureSegment(from: start, to: end, kind: .text, terminatesWithHardBreak: false)
                    return
                }

                func isGlueOnlyRange(from start: Int, to end: Int) -> Bool {
                    guard start < end else { return false }
                    for index in start..<end where !isGlueCharacter(utf16Chars[index]) {
                        return false
                    }
                    return true
                }

                var tokenRanges: [NSRange] = []
                var currentTokenRange = wordRanges[0]

                for wordRange in wordRanges.dropFirst() {
                    let gapStart = NSMaxRange(currentTokenRange)
                    let gapEnd = wordRange.location

                    if isGlueOnlyRange(from: gapStart, to: gapEnd) {
                        currentTokenRange = NSRange(
                            location: currentTokenRange.location,
                            length: NSMaxRange(wordRange) - currentTokenRange.location
                        )
                        continue
                    }

                    tokenRanges.append(currentTokenRange)
                    if gapStart < gapEnd {
                        tokenRanges.append(NSRange(location: gapStart, length: gapEnd - gapStart))
                    }
                    currentTokenRange = wordRange
                }
                tokenRanges.append(currentTokenRange)

                if let firstTokenRange = tokenRanges.first, start < firstTokenRange.location {
                    tokenRanges.insert(
                        NSRange(location: start, length: firstTokenRange.location - start),
                        at: 0
                    )
                }

                if let lastTokenRange = tokenRanges.last {
                    let lastTokenEnd = NSMaxRange(lastTokenRange)
                    if lastTokenEnd < end {
                        tokenRanges.append(
                            NSRange(location: lastTokenEnd, length: end - lastTokenEnd)
                        )
                    }
                }

                let alphanumerics = CharacterSet.alphanumerics
                let decimalDigits = CharacterSet.decimalDigits
                let urlPunctuation = CharacterSet(charactersIn: "-._~:/?#[]@!$&'()*+,;=%")
                let numericPunctuation = CharacterSet(charactersIn: "-/:.,+()#")
                let cjkPunctuation = CharacterSet(charactersIn: "，。！？：；、（）《》「」『』【】〈〉〔〕［］｛｝—…·・")
                let closingPunctuation = CharacterSet(charactersIn: ".,;:!?%)]}'\"”’")

                func tokenText(for range: NSRange) -> String {
                    fullNSString.substring(with: range)
                }

                func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
                    switch scalar.value {
                    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
                        return true
                    default:
                        return false
                    }
                }

                func isURLSafeToken(_ text: String) -> Bool {
                    !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
                        alphanumerics.contains(scalar) || urlPunctuation.contains(scalar)
                    }
                }

                func isURLLikeToken(_ text: String) -> Bool {
                    guard isURLSafeToken(text) else { return false }
                    return text.contains("://") || text.contains(".") || text.contains("@") || text.contains("/") || text.contains("?") || text.contains("#")
                }

                func isClosingPunctuationToken(_ text: String) -> Bool {
                    !text.isEmpty && text.unicodeScalars.allSatisfy(closingPunctuation.contains)
                }

                func isNumericStickyToken(_ text: String) -> Bool {
                    !text.isEmpty
                        && text.unicodeScalars.contains(where: decimalDigits.contains)
                        && text.unicodeScalars.allSatisfy { scalar in
                            decimalDigits.contains(scalar) || numericPunctuation.contains(scalar)
                        }
                }

                func isCJKStickyToken(_ text: String) -> Bool {
                    !text.isEmpty
                        && text.unicodeScalars.contains(where: isCJKScalar)
                        && text.unicodeScalars.allSatisfy { scalar in
                            isCJKScalar(scalar) || decimalDigits.contains(scalar) || cjkPunctuation.contains(scalar)
                        }
                }

                func shouldMergeAdjacentTextTokens(left leftRange: NSRange, right rightRange: NSRange) -> Bool {
                    let leftText = tokenText(for: leftRange)
                    let rightText = tokenText(for: rightRange)

                    if isClosingPunctuationToken(rightText) {
                        return true
                    }

                    if isURLLikeToken(leftText) && isURLSafeToken(rightText) {
                        return true
                    }

                    let combinedText = leftText + rightText
                    if isURLSafeToken(leftText) && isURLLikeToken(combinedText) {
                        return true
                    }

                    if isNumericStickyToken(combinedText) {
                        return true
                    }

                    if isCJKStickyToken(combinedText) {
                        return true
                    }

                    return false
                }

                var mergedTokenRanges: [NSRange] = []
                for tokenRange in tokenRanges {
                    guard let lastRange = mergedTokenRanges.last else {
                        mergedTokenRanges.append(tokenRange)
                        continue
                    }

                    if NSMaxRange(lastRange) == tokenRange.location,
                       shouldMergeAdjacentTextTokens(left: lastRange, right: tokenRange) {
                        mergedTokenRanges[mergedTokenRanges.count - 1] = NSRange(
                            location: lastRange.location,
                            length: NSMaxRange(tokenRange) - lastRange.location
                        )
                    } else {
                        mergedTokenRanges.append(tokenRange)
                    }
                }

                for tokenRange in mergedTokenRanges {
                    measureSegment(
                        from: tokenRange.location,
                        to: NSMaxRange(tokenRange),
                        kind: .text,
                        terminatesWithHardBreak: false
                    )
                }
            }
            
            // Scan through UTF-16 code units directly
            for i in range.location ..< (range.location + range.length) {
                let char = utf16Chars[i]
                
                // Fast basic checks for word boundaries
                // 0x000A = LF (\n), 0x000D = CR (\r)
                let isNewlineChar = char == 0x000A || char == 0x000D || char == 0x2028 || char == 0x2029
                // 0x00AD = Soft Hyphen
                let isSoftHyphenChar = char == 0x00AD
                // 0x0020 = Space, 0x0009 = Tab, 0x200B = Zero Width Space
                // Non-breaking glue characters such as NBSP and Word Joiner intentionally
                // stay in text segments so they do not create break opportunities.
                let isSpaceChar = char == 0x0020 || char == 0x0009 || char == 0x200B
                
                if isSoftHyphenChar {
                    if i > segmentStartIndex {
                        if isCurrentSpace {
                            measureSegment(
                                from: segmentStartIndex,
                                to: i,
                                kind: .space,
                                terminatesWithHardBreak: false
                            )
                        } else {
                            measureLocalizedTextRange(from: segmentStartIndex, to: i)
                        }
                    }
                    preparedText.append(
                        width: 0,
                        kind: .softHyphen,
                        height: lineHeight,
                        lineEndFitAdvance: discretionaryHyphenWidth,
                        lineEndPaintAdvance: discretionaryHyphenWidth
                    )
                    segmentStartIndex = i + 1
                    isCurrentSpace = false
                } else if isNewlineChar {
                    if isCurrentSpace {
                        measureSegment(
                            from: segmentStartIndex,
                            to: i,
                            kind: .space,
                            terminatesWithHardBreak: true
                        )
                    } else {
                        measureLocalizedTextRange(from: segmentStartIndex, to: i)
                        preparedText.append(width: 0, kind: .hardBreak, height: lineHeight)
                    }
                    segmentStartIndex = i + 1
                    isCurrentSpace = false // Reset after newline
                } else if isSpaceChar != isCurrentSpace {
                    if i > segmentStartIndex {
                        if isCurrentSpace {
                            measureSegment(
                                from: segmentStartIndex,
                                to: i,
                                kind: .space,
                                terminatesWithHardBreak: false
                            )
                        } else {
                            measureLocalizedTextRange(from: segmentStartIndex, to: i)
                        }
                    }
                    segmentStartIndex = i
                    isCurrentSpace = isSpaceChar
                }
            }
            
            // Final segment in range
            if segmentStartIndex < range.location + range.length {
                if isCurrentSpace {
                    measureSegment(
                        from: segmentStartIndex,
                        to: range.location + range.length,
                        kind: .space,
                        terminatesWithHardBreak: false
                    )
                } else {
                    measureLocalizedTextRange(from: segmentStartIndex, to: range.location + range.length)
                }
            }
        }
        
        return preparedText
    }

    private func preparedTextCacheKey(for attributedString: NSAttributedString) -> PreparedTextCacheKey {
        var runs: [PreparedTextRunKey] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let font = attributes[.font] as? Font
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle

            runs.append(
                PreparedTextRunKey(
                    location: range.location,
                    length: range.length,
                    fontName: font?.fontName ?? "",
                    pointSizeMilli: Self.milliUnits(for: font?.pointSize ?? 0),
                    lineHeightMultipleMilli: Self.milliUnits(for: paragraphStyle?.lineHeightMultiple ?? 0),
                    headIndentMilli: Self.milliUnits(for: paragraphStyle?.headIndent ?? 0),
                    firstLineHeadIndentMilli: Self.milliUnits(for: paragraphStyle?.firstLineHeadIndent ?? 0)
                )
            )
        }

        return PreparedTextCacheKey(
            string: attributedString.string,
            localeIdentifier: Locale.current.identifier,
            runs: runs
        )
    }

    private static func milliUnits(for value: CGFloat) -> Int {
        Int((value * 1000).rounded())
    }
}
