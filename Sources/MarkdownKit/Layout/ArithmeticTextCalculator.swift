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

    private struct FontCacheKey: Hashable {
        let fontName: String
        let pointSizeMilli: Int
    }

    private static let widthCacheLock = NSLock()
    private static nonisolated(unsafe) var cachedWidths: [FontCacheKey: [String: CGFloat]] = [:]

    enum SegmentKind {
        case text
        case space
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
            case .space, .hardBreak:
                return 0
            }
        }

        func lineEndPaintAdvance(for width: CGFloat) -> CGFloat {
            switch self {
            case .text, .space:
                return width
            case .hardBreak:
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
        var fontNames: [String] = []
        var pointSizes: [CGFloat] = []
        var heights: [CGFloat] = []
        var chunks: [Chunk] = []
        var headIndent: CGFloat = 0
        var firstLineHeadIndent: CGFloat = 0
        
        mutating func append(
            width: CGFloat,
            kind: SegmentKind,
            height: CGFloat,
            text: String = "",
            fontName: String = "",
            pointSize: CGFloat = 0
        ) {
            self.widths.append(width)
            self.kinds.append(kind)
            self.lineEndFitAdvances.append(kind.lineEndFitAdvance(for: width))
            self.lineEndPaintAdvances.append(kind.lineEndPaintAdvance(for: width))
            self.segmentTexts.append(text)
            self.fontNames.append(fontName)
            self.pointSizes.append(pointSize)
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

    private static func cachedWidth(for text: String, fontKey: FontCacheKey) -> CGFloat? {
        widthCacheLock.lock()
        defer { widthCacheLock.unlock() }
        return cachedWidths[fontKey]?[text]
    }

    private static func storeCachedWidth(_ width: CGFloat, for text: String, fontKey: FontCacheKey) {
        widthCacheLock.lock()
        defer { widthCacheLock.unlock() }
        var fontWidths = cachedWidths[fontKey] ?? [:]
        fontWidths[text] = width
        cachedWidths[fontKey] = fontWidths
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
        return buildPreparedText(from: attributedString)
    }

    /// Lays out a previously prepared payload at a specific width using pure arithmetic.
    func layout(prepared preparedText: PreparedText, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        guard !preparedText.widths.isEmpty else { return .zero }

        var currentLineAdvance: CGFloat = 0
        var currentLinePaintWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxComputedWidth: CGFloat = 0
        var lineCount = 0

        func appendOversizedTextSegment(
            text: String,
            fontName: String,
            pointSize: CGFloat,
            height: CGFloat
        ) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, pointSize, nil)
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
                currentLinePaintWidth = lineWidth
                currentLineHeight = max(currentLineHeight, height)
                start += count

                if start < nsText.length {
                    totalHeight += currentLineHeight
                    maxComputedWidth = max(maxComputedWidth, currentLinePaintWidth + currentIndent)
                    lineCount += 1
                    currentLineAdvance = 0
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
            let fontName = preparedText.fontNames[index]
            let pointSize = preparedText.pointSizes[index]
            let kind = preparedText.kinds[index]
            let height = preparedText.heights[index]
            let currentIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
            let availableWidth = maxWidth - currentIndent
            
            if chunk.kind == .hardBreak {
                totalHeight += max(currentLineHeight, height)
                let visibleLineWidth = currentLinePaintWidth > 0 ? currentLinePaintWidth + currentIndent : 0
                maxComputedWidth = max(maxComputedWidth, visibleLineWidth)
                currentLineAdvance = 0
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
                maxComputedWidth = max(maxComputedWidth, currentLinePaintWidth + currentIndent)
                
                lineCount += 1
                if kind.isSpace {
                    currentLineAdvance = 0
                    currentLinePaintWidth = 0
                    currentLineHeight = 0
                } else {
                    let nextIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
                    let nextAvailableWidth = maxWidth - nextIndent
                    if kind == .text && width > nextAvailableWidth && !segmentText.isEmpty {
                        currentLineAdvance = 0
                        currentLinePaintWidth = 0
                        currentLineHeight = 0
                        appendOversizedTextSegment(
                            text: segmentText,
                            fontName: fontName,
                            pointSize: pointSize,
                            height: height
                        )
                    } else {
                        currentLineAdvance = width
                        currentLinePaintWidth = lineEndPaintAdvance
                        currentLineHeight = height
                    }
                }
            } else if nextLineFitWidth > availableWidth && kind == .text && !segmentText.isEmpty {
                appendOversizedTextSegment(
                    text: segmentText,
                    fontName: fontName,
                    pointSize: pointSize,
                    height: height
                )
            } else {
                currentLineAdvance = nextLineAdvance
                currentLinePaintWidth = nextLinePaintWidth
                currentLineHeight = max(currentLineHeight, height)
            }
        }
        
        // Add final line height if it wasn't empty
        if currentLineAdvance > 0 || totalHeight == 0 {
            let currentIndent = (lineCount == 0) ? preparedText.firstLineHeadIndent : preparedText.headIndent
            totalHeight += currentLineHeight
            let visibleLineWidth = currentLinePaintWidth > 0 ? currentLinePaintWidth + currentIndent : 0
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
            
            // Convert platform Font to CTFont
            #if canImport(UIKit)
            let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
            let lineHeightMetric = font.lineHeight
            #elseif canImport(AppKit)
            let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
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
                        fontName: kind == .text ? font.fontName : "",
                        pointSize: kind == .text ? font.pointSize : 0
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
                            fontName: kind == .text ? font.fontName : "",
                            pointSize: kind == .text ? font.pointSize : 0
                        )
                    } else {
                        Self.storeCachedWidth(0, for: segmentText, fontKey: fontCacheKey)
                        preparedText.append(
                            width: 0,
                            kind: kind,
                            height: lineHeight,
                            text: kind == .text ? segmentText : "",
                            fontName: kind == .text ? font.fontName : "",
                            pointSize: kind == .text ? font.pointSize : 0
                        )
                    }
                }
                
                if terminatesWithHardBreak {
                    preparedText.append(width: 0, kind: .hardBreak, height: lineHeight)
                }
            }
            
            // Scan through UTF-16 code units directly
            for i in range.location ..< (range.location + range.length) {
                let char = utf16Chars[i]
                
                // Fast basic checks for word boundaries
                // 0x000A = LF (\n), 0x000D = CR (\r)
                let isNewlineChar = char == 0x000A || char == 0x000D || char == 0x2028 || char == 0x2029
                // 0x0020 = Space, 0x0009 = Tab
                let isSpaceChar = char == 0x0020 || char == 0x0009
                
                if isNewlineChar {
                    measureSegment(
                        from: segmentStartIndex,
                        to: i,
                        kind: isCurrentSpace ? .space : .text,
                        terminatesWithHardBreak: true
                    )
                    segmentStartIndex = i + 1
                    isCurrentSpace = false // Reset after newline
                } else if isSpaceChar != isCurrentSpace {
                    if i > segmentStartIndex {
                        measureSegment(
                            from: segmentStartIndex,
                            to: i,
                            kind: isCurrentSpace ? .space : .text,
                            terminatesWithHardBreak: false
                        )
                    }
                    segmentStartIndex = i
                    isCurrentSpace = isSpaceChar
                }
            }
            
            // Final segment in range
            if segmentStartIndex < range.location + range.length {
                measureSegment(
                    from: segmentStartIndex,
                    to: range.location + range.length,
                    kind: isCurrentSpace ? .space : .text,
                    terminatesWithHardBreak: false
                )
            }
        }
        
        return preparedText
    }
}
