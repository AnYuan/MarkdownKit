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
final class ArithmeticTextCalculator {

    struct PreparedTextProfile {
        var containsUnsupportedScript = false
        var containsAttachment = false
        var containsAllGlyphFallbackParagraph = false
        var containsAttributeSplitGrapheme = false
        var containsPositionDependentTab = false
        var containsInvalidFontPointSize = false

        var supportsArithmeticLayout: Bool {
            !containsUnsupportedScript
                && !containsAttachment
                && !containsAllGlyphFallbackParagraph
                && !containsAttributeSplitGrapheme
                && !containsPositionDependentTab
                && !containsInvalidFontPointSize
        }
    }

    private struct PreparedTextParagraphStyleKey: Hashable {
        let lineHeightMultiple: CGFloat
        let headIndent: CGFloat
        let firstLineHeadIndent: CGFloat
        let paragraphSpacing: CGFloat
        let paragraphSpacingBefore: CGFloat
    }

    private struct PreparedTextRunKey: Hashable {
        let location: Int
        let length: Int
        let fontName: String
        let pointSize: CGFloat
        let paragraphStyleIndex: Int
    }

    private struct PreparedTextCacheKey: Hashable {
        let string: String
        let localeIdentifier: String
        let paragraphStyles: [PreparedTextParagraphStyleKey]
        let runs: [PreparedTextRunKey]
    }

    /// NSObject wrapper around `PreparedTextCacheKey` so it can be used as `NSCache` key.
    private final class PreparedTextCacheKeyObject: NSObject {
        let value: PreparedTextCacheKey
        private let cachedHash: Int

        init(_ value: PreparedTextCacheKey) {
            self.value = value
            self.cachedHash = value.hashValue
        }

        override var hash: Int { cachedHash }

        override func isEqual(_ object: Any?) -> Bool {
            (object as? PreparedTextCacheKeyObject)?.value == value
        }
    }

    /// Class wrapper because `NSCache` requires class values; `PreparedText` is a struct.
    private final class PreparedTextWrapper {
        let value: PreparedText

        init(_ value: PreparedText) {
            self.value = value
        }
    }

    /// NSCache is internally thread-safe; soft `countLimit` prevents unbounded growth.
    private static nonisolated(unsafe) let cachedPreparedTexts: NSCache<PreparedTextCacheKeyObject, PreparedTextWrapper> = {
        let cache = NSCache<PreparedTextCacheKeyObject, PreparedTextWrapper>()
        cache.countLimit = 1_024
        return cache
    }()

    // MARK: - Test diagnostics (do not use in production paths)
    //
    // The lock and its backing counters exist purely so tests can assert on
    // cache hit/miss routing. They are compiled out entirely in Release so
    // Release builds never pay for lock acquisition on the hot lookup path;
    // the accessors below still compile (returning 0) so Release test targets
    // that reference them keep building.
    #if DEBUG
    private static let testCounterLock = NSLock()
    private static nonisolated(unsafe) var preparedTextCacheHits: Int = 0
    private static nonisolated(unsafe) var preparedTextCacheMisses: Int = 0
    #endif

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

    struct Paragraph {
        let chunkRange: Range<Int>
        let firstLineHeadIndent: CGFloat
        let headIndent: CGFloat
        let paragraphSpacingBefore: CGFloat
        let paragraphSpacingAfter: CGFloat
        let emptyLineHeight: CGFloat
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
        /// Distance from the top of a line fragment to the baseline for each
        /// segment. `height - baselineOffset` is the segment's below-baseline
        /// extent. Keeping both sides lets a line combine a tall ascender from
        /// one font with a deeper fallback-font descender from another, matching
        /// TextKit's mixed-font line-box construction.
        var baselineOffsets: [CGFloat] = []
        /// Whether CoreText retained the requested font for at least one glyph
        /// belonging to a visible character in each shaped segment.
        var containsRequestedFontRuns: [Bool] = []
        /// Whether each segment contains any non-whitespace,
        /// non-default-ignorable character. Keeping visibility separate from
        /// requested-font evidence prevents control-only runs from masking a
        /// fallback-only visible segment on the same line.
        var containsVisibleCharacters: [Bool] = []
        var chunks: [Chunk] = []
        var headIndent: CGFloat = 0
        var firstLineHeadIndent: CGFloat = 0
        var paragraphs: [Paragraph] = []

        mutating func reserveCapacity(segments: Int, paragraphs paragraphCount: Int) {
            widths.reserveCapacity(segments)
            kinds.reserveCapacity(segments)
            lineEndFitAdvances.reserveCapacity(segments)
            lineEndPaintAdvances.reserveCapacity(segments)
            segmentTexts.reserveCapacity(segments)
            ctFonts.reserveCapacity(segments)
            heights.reserveCapacity(segments)
            baselineOffsets.reserveCapacity(segments)
            containsRequestedFontRuns.reserveCapacity(segments)
            containsVisibleCharacters.reserveCapacity(segments)
            chunks.reserveCapacity(segments)
            paragraphs.reserveCapacity(paragraphCount)
        }

        mutating func append(
            width: CGFloat,
            kind: SegmentKind,
            height: CGFloat,
            text: String = "",
            ctFont: CTFont? = nil,
            baselineOffset: CGFloat? = nil,
            containsRequestedFontRun: Bool = true,
            containsVisibleCharacter: Bool? = nil,
            lineEndFitAdvance: CGFloat? = nil,
            lineEndPaintAdvance: CGFloat? = nil
        ) {
            widths.append(width)
            kinds.append(kind)
            lineEndFitAdvances.append(lineEndFitAdvance ?? kind.lineEndFitAdvance(for: width))
            lineEndPaintAdvances.append(lineEndPaintAdvance ?? kind.lineEndPaintAdvance(for: width))
            segmentTexts.append(text)
            ctFonts.append(ctFont)
            heights.append(height)
            baselineOffsets.append(baselineOffset ?? height)
            containsRequestedFontRuns.append(containsRequestedFontRun)
            containsVisibleCharacters.append(containsVisibleCharacter ?? (kind == .text))
            chunks.append(
                Chunk(
                    kind: kind.isHardBreak ? .hardBreak : .content,
                    segmentIndex: widths.count - 1
                )
            )
        }
    }

    init() {}

    static func preparedTextCacheHitsForTesting() -> Int {
        #if DEBUG
        testCounterLock.lock()
        defer { testCounterLock.unlock() }
        return preparedTextCacheHits
        #else
        return 0
        #endif
    }

    static func preparedTextCacheMissesForTesting() -> Int {
        #if DEBUG
        testCounterLock.lock()
        defer { testCounterLock.unlock() }
        return preparedTextCacheMisses
        #else
        return 0
        #endif
    }

    /// Clears the prepared-text cache. Must keep clearing the real production
    /// cache in Release (benchmarks rely on this), even though the diagnostic
    /// counters themselves only exist in DEBUG.
    static func resetPreparedTextCacheForTesting() {
        cachedPreparedTexts.removeAllObjects()
        #if DEBUG
        testCounterLock.lock()
        preparedTextCacheHits = 0
        preparedTextCacheMisses = 0
        testCounterLock.unlock()
        #endif
    }

    func profile(for attributedString: NSAttributedString) -> PreparedTextProfile {
        guard attributedString.length > 0 else { return PreparedTextProfile() }

        var profile = PreparedTextProfile()
        let attributedRunProfile = Self.attributedRunProfile(
            in: attributedString
        )
        profile.containsAttachment = attributedRunProfile.containsAttachment
        profile.containsAttributeSplitGrapheme =
            attributedRunProfile.containsAttributeSplitGrapheme
        profile.containsInvalidFontPointSize =
            attributedRunProfile.containsInvalidFontPointSize
        if profile.containsAttachment
            || profile.containsAttributeSplitGrapheme
            || profile.containsInvalidFontPointSize {
            return profile
        }

        for scalar in attributedString.string.unicodeScalars {
            if scalar.value == 0x0009 {
                profile.containsPositionDependentTab = true
            }
            if Self.requiresTextKitFallback(for: scalar) {
                profile.containsUnsupportedScript = true
            }
            if profile.containsPositionDependentTab,
               profile.containsUnsupportedScript {
                break
            }
        }

        #if canImport(AppKit)
        if !profile.containsUnsupportedScript,
           !profile.containsPositionDependentTab {
            let glyphCoverage = Self.appKitGlyphCoverage(in: attributedString)
            profile.containsAllGlyphFallbackParagraph =
                glyphCoverage.containsAllGlyphFallbackParagraph
        }
        #endif

        return profile
    }

    /// Calculates the exact bounding size for a given attributed string constrained to a width.
    ///
    /// - Parameters:
    ///   - attributedString: The pure-text themed string to measure.
    ///   - maxWidth: The maximum width of the containing viewport.
    /// - Returns: The precise `CGSize` necessary to display the text without clipping.
    func calculateSize(for attributedString: NSAttributedString, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        let preparedText = prepare(attributedString: attributedString)
        return layout(prepared: preparedText, constrainedToWidth: maxWidth)
    }

    /// Prepares a pure-text attributed string into a width-independent structure-of-arrays payload.
    func prepare(attributedString: NSAttributedString) -> PreparedText {
        guard attributedString.length > 0 else { return PreparedText() }
        let cacheKey = PreparedTextCacheKeyObject(preparedTextCacheKey(for: attributedString))
        if let cachedPreparedText = Self.cachedPreparedText(for: cacheKey) {
            return cachedPreparedText
        }

        let preparedText = ArithmeticTextMeasurer.prepare(attributedString: attributedString)
        Self.storePreparedText(preparedText, for: cacheKey)
        return preparedText
    }

    /// Lays out a previously prepared payload at a specific width using pure arithmetic.
    func layout(prepared preparedText: PreparedText, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        ArithmeticTextLineBreaker.layout(prepared: preparedText, constrainedToWidth: maxWidth)
    }

    func layoutOutcome(
        prepared preparedText: PreparedText,
        constrainedToWidth maxWidth: CGFloat,
        stopWhenTextKitFallbackIsRequired: Bool = false,
        shouldCancel: (() -> Bool)? = nil,
        onOversizedLine: (() -> Void)? = nil
    ) -> ArithmeticTextLineBreaker.LayoutOutcome {
        ArithmeticTextLineBreaker.layoutOutcome(
            prepared: preparedText,
            constrainedToWidth: maxWidth,
            stopWhenTextKitFallbackIsRequired: stopWhenTextKitFallbackIsRequired,
            shouldCancel: shouldCancel,
            onOversizedLine: onOversizedLine
        )
    }

    private static func cachedPreparedText(for key: PreparedTextCacheKeyObject) -> PreparedText? {
        if let wrapper = cachedPreparedTexts.object(forKey: key) {
            #if DEBUG
            testCounterLock.lock()
            preparedTextCacheHits += 1
            testCounterLock.unlock()
            #endif
            return wrapper.value
        }
        #if DEBUG
        testCounterLock.lock()
        preparedTextCacheMisses += 1
        testCounterLock.unlock()
        #endif
        return nil
    }

    private static func storePreparedText(_ preparedText: PreparedText, for key: PreparedTextCacheKeyObject) {
        cachedPreparedTexts.setObject(PreparedTextWrapper(preparedText), forKey: key)
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

    private struct AttributedRunProfile {
        var containsAttachment = false
        var containsAttributeSplitGrapheme = false
        var containsInvalidFontPointSize = false
    }

    /// Arithmetic preparation shapes attributed runs independently and keys
    /// their platform fonts by millipoints. An extended grapheme that crosses a
    /// run boundary therefore needs TextKit, even when only a non-font attribute
    /// changes, while a non-cacheable point size must fail closed before integer
    /// key conversion. Validate both on every platform before any AppKit-only
    /// glyph coverage shortcut can return early.
    private static func attributedRunProfile(
        in attributedString: NSAttributedString
    ) -> AttributedRunProfile {
        let length = attributedString.length
        guard length > 0 else { return AttributedRunProfile() }

        let string = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: length)
        var profile = AttributedRunProfile()
        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, stop in
            if attributes[.attachment] != nil {
                profile.containsAttachment = true
                stop.pointee = true
                return
            }
            if let font = attributes[.font] as? Font,
               !ArithmeticTextMeasurer.supportsArithmeticPointSize(font.pointSize) {
                profile.containsInvalidFontPointSize = true
                stop.pointee = true
                return
            }

            let boundary = NSMaxRange(range)
            guard boundary > 0, boundary < length else { return }

            let composedRange = string.rangeOfComposedCharacterSequence(at: boundary)
            if composedRange.location < boundary {
                profile.containsAttributeSplitGrapheme = true
                stop.pointee = true
            }
        }
        return profile
    }

    #if canImport(AppKit)
    private struct AppKitGlyphCoverage {
        var containsAllGlyphFallbackParagraph = false
    }

    private struct VisibleGlyphCoverage {
        var sawVisibleCharacter = false
        var requestedFontSuppliesGlyph = false
    }

    /// AppKit's line box for a paragraph whose requested font supplies no glyphs
    /// changes with process-global fallback state. Such paragraphs cannot have a
    /// deterministic arithmetic height, so routing must fail closed to TextKit.
    /// Nominal glyph lookup avoids populating CoreText's fallback dictionaries and
    /// normally returns after the first visible grapheme for supported fonts.
    private static func appKitGlyphCoverage(
        in attributedString: NSAttributedString
    ) -> AppKitGlyphCoverage {
        let string = attributedString.string as NSString
        var nextParagraphLocation = 0
        var result = AppKitGlyphCoverage()

        while nextParagraphLocation < string.length {
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
            let paragraphCoverage = visibleGlyphCoverage(
                in: attributedString,
                string: string,
                range: contentRange
            )

            if paragraphCoverage.sawVisibleCharacter,
               !paragraphCoverage.requestedFontSuppliesGlyph {
                result.containsAllGlyphFallbackParagraph = true
                return result
            }
            nextParagraphLocation = paragraphEnd
        }

        return result
    }

    private static func visibleGlyphCoverage(
        in attributedString: NSAttributedString,
        string: NSString,
        range: NSRange
    ) -> VisibleGlyphCoverage {
        var coverage = VisibleGlyphCoverage()
        let rangeEnd = NSMaxRange(range)
        var location = range.location

        while location < rangeEnd {
            let composedRange = NSIntersectionRange(
                string.rangeOfComposedCharacterSequence(at: location),
                range
            )
            guard composedRange.length > 0 else {
                location += 1
                continue
            }
            location = NSMaxRange(composedRange)

            guard ArithmeticTextMeasurer.containsVisibleCharacter(
                in: string,
                range: composedRange
            ) else { continue }
            coverage.sawVisibleCharacter = true

            let attributes = attributedString.attributes(
                at: composedRange.location,
                effectiveRange: nil
            )
            let requestedFont = (attributes[.font] as? Font)
                ?? ArithmeticTextMeasurer.defaultTextKitFont

            if requestedFontSuppliesEntireCluster(
                in: string,
                range: composedRange,
                ctFont: requestedFont as CTFont
            ) {
                coverage.requestedFontSuppliesGlyph = true
                return coverage
            }
        }

        return coverage
    }

    private static func requestedFontSuppliesEntireCluster(
        in string: NSString,
        range: NSRange,
        ctFont: CTFont
    ) -> Bool {
        if range.length == 1 {
            var character = string.character(at: range.location)
            var glyph: CGGlyph = 0
            return CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1)
                && glyph != 0
        }

        let cluster = string.substring(with: range)
        let characters = Array(cluster.utf16)
        guard !characters.isEmpty else { return false }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let mapsEveryCharacter = characters.withUnsafeBufferPointer { charactersBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphsBuffer in
                CTFontGetGlyphsForCharacters(
                    ctFont,
                    charactersBuffer.baseAddress!,
                    glyphsBuffer.baseAddress!,
                    charactersBuffer.count
                )
            }
        }
        return mapsEveryCharacter && glyphs.contains(where: { $0 != 0 })
    }
    #endif

    private func preparedTextCacheKey(for attributedString: NSAttributedString) -> PreparedTextCacheKey {
        var paragraphStyles: [PreparedTextParagraphStyleKey] = []
        var runs: [PreparedTextRunKey] = []
        let estimatedRunCount = min(max(attributedString.length / 40, 8), 512)
        paragraphStyles.reserveCapacity(min(estimatedRunCount, 256))
        runs.reserveCapacity(estimatedRunCount)
        var hasLastParagraphStyle = false
        var lastParagraphStyle: NSParagraphStyle?
        var lastParagraphStyleIndex = 0
        let fullRange = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let font = attributes[.font] as? Font
            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
            let paragraphStyleIndex: Int

            if hasLastParagraphStyle, paragraphStyle === lastParagraphStyle {
                paragraphStyleIndex = lastParagraphStyleIndex
            } else {
                let paragraphStyleKey = Self.preparedParagraphStyleKey(for: paragraphStyle)
                paragraphStyleIndex = paragraphStyles.count
                paragraphStyles.append(paragraphStyleKey)
                hasLastParagraphStyle = true
                lastParagraphStyle = paragraphStyle
                lastParagraphStyleIndex = paragraphStyleIndex
            }

            runs.append(
                PreparedTextRunKey(
                    location: range.location,
                    length: range.length,
                    fontName: font?.fontName ?? "",
                    pointSize: font?.pointSize ?? 0,
                    paragraphStyleIndex: paragraphStyleIndex
                )
            )
        }

        return PreparedTextCacheKey(
            string: attributedString.string,
            localeIdentifier: Locale.current.identifier,
            paragraphStyles: paragraphStyles,
            runs: runs
        )
    }

    private static func preparedParagraphStyleKey(
        for paragraphStyle: NSParagraphStyle?
    ) -> PreparedTextParagraphStyleKey {
        PreparedTextParagraphStyleKey(
            lineHeightMultiple: normalizedLineHeightMultiple(
                paragraphStyle?.lineHeightMultiple
            ),
            headIndent: normalizedParagraphMetric(paragraphStyle?.headIndent),
            firstLineHeadIndent: normalizedParagraphMetric(
                paragraphStyle?.firstLineHeadIndent
            ),
            paragraphSpacing: normalizedParagraphMetric(paragraphStyle?.paragraphSpacing),
            paragraphSpacingBefore: normalizedParagraphMetric(
                paragraphStyle?.paragraphSpacingBefore
            )
        )
    }

    private static func normalizedParagraphMetric(_ value: CGFloat?) -> CGFloat {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return value
    }

    private static func normalizedLineHeightMultiple(_ value: CGFloat?) -> CGFloat {
        guard let value, value.isFinite, value > 0 else { return 1 }
        return value
    }
}
