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

    /// NSObject wrapper around `PreparedTextCacheKey` so it can be used as `NSCache` key.
    private final class PreparedTextCacheKeyObject: NSObject {
        let value: PreparedTextCacheKey

        init(_ value: PreparedTextCacheKey) {
            self.value = value
        }

        override var hash: Int { value.hashValue }

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
            widths.append(width)
            kinds.append(kind)
            lineEndFitAdvances.append(lineEndFitAdvance ?? kind.lineEndFitAdvance(for: width))
            lineEndPaintAdvances.append(lineEndPaintAdvance ?? kind.lineEndPaintAdvance(for: width))
            segmentTexts.append(text)
            ctFonts.append(ctFont)
            heights.append(height)
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
        let cacheKey = preparedTextCacheKey(for: attributedString)
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

    private static func cachedPreparedText(for key: PreparedTextCacheKey) -> PreparedText? {
        let keyObject = PreparedTextCacheKeyObject(key)
        if let wrapper = cachedPreparedTexts.object(forKey: keyObject) {
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

    private static func storePreparedText(_ preparedText: PreparedText, for key: PreparedTextCacheKey) {
        let keyObject = PreparedTextCacheKeyObject(key)
        cachedPreparedTexts.setObject(PreparedTextWrapper(preparedText), forKey: keyObject)
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
