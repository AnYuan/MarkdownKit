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

    /// Structure of Arrays (SoA) representing the segmented text for extremely fast iteration.
    struct PreparedText {
        var widths: [CGFloat] = []
        var isSpace: [Bool] = []
        var isNewline: [Bool] = []
        var heights: [CGFloat] = []
        
        mutating func append(width: CGFloat, isSpace: Bool, isNewline: Bool, height: CGFloat) {
            self.widths.append(width)
            self.isSpace.append(isSpace)
            self.isNewline.append(isNewline)
            self.heights.append(height)
        }
    }

    public init() {}

    /// Calculates the exact bounding size for a given attributed string constrained to a width.
    ///
    /// - Parameters:
    ///   - attributedString: The pure-text themed string to measure.
    ///   - maxWidth: The maximum width of the containing viewport.
    /// - Returns: The precise `CGSize` necessary to display the text without clipping.
    public func calculateSize(for attributedString: NSAttributedString, constrainedToWidth maxWidth: CGFloat) -> CGSize {
        guard attributedString.length > 0 else { return .zero }

        let preparedText = prepare(attributedString: attributedString)
        
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxComputedWidth: CGFloat = 0
        
        for i in 0..<preparedText.widths.count {
            let width = preparedText.widths[i]
            let isSpace = preparedText.isSpace[i]
            let isNewline = preparedText.isNewline[i]
            let height = preparedText.heights[i]
            
            if isNewline {
                totalHeight += max(currentLineHeight, height)
                currentLineWidth = 0
                currentLineHeight = 0
                continue
            }
            
            if currentLineWidth + width > maxWidth && currentLineWidth > 0 {
                // Break line
                totalHeight += currentLineHeight
                maxComputedWidth = max(maxComputedWidth, currentLineWidth)
                
                // If it's a space that caused the break, it might hang in CSS, 
                // but usually it starts the next line (or gets discarded at the start).
                // We'll mimic basic wrap behavior: drop leading spaces on new lines.
                if isSpace {
                    currentLineWidth = 0
                    currentLineHeight = 0
                } else {
                    currentLineWidth = width
                    currentLineHeight = height
                }
            } else {
                currentLineWidth += width
                currentLineHeight = max(currentLineHeight, height)
            }
        }
        
        // Add final line height if it wasn't empty
        if currentLineWidth > 0 || totalHeight == 0 {
            totalHeight += currentLineHeight
            maxComputedWidth = max(maxComputedWidth, currentLineWidth)
        }
        
        return CGSize(width: ceil(maxComputedWidth), height: ceil(totalHeight))
    }

    /// Segments the attributed string into words and whitespace, measuring the exact width
    /// of each segment using CoreText, and returning a Structure of Arrays (SoA) payload.
    private func prepare(attributedString: NSAttributedString) -> PreparedText {
        var preparedText = PreparedText()
        let fullString = attributedString.string
        let utf16Chars = Array(fullString.utf16) // Single allocation of the entire text buffer
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            guard let font = attributes[.font] as? Font else { return }
            
            // Convert platform Font to CTFont
            #if canImport(UIKit)
            let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
            #elseif canImport(AppKit)
            let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
            #endif
            
            // Approximate line height based on font metrics
            let ascent = CTFontGetAscent(ctFont)
            let descent = CTFontGetDescent(ctFont)
            let leading = CTFontGetLeading(ctFont)
            
            // Adjust line height multiplier if specified in paragraph style
            var lineHeight = ascent + descent + leading
            if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
                let multiplier = paragraphStyle.lineHeightMultiple
                if multiplier > 0 {
                    lineHeight *= multiplier
                }
            }
            
            // Reusable buffers for this font range to avoid allocating per-word
            var glyphs = [CGGlyph](repeating: 0, count: range.length)
            var advances = [CGSize](repeating: .zero, count: range.length)
            
            var segmentStartIndex = range.location
            var isCurrentSpace = false
            
            // Inline helper to measure a chunk without allocations
            func measureSegment(from start: Int, to end: Int, isSpace: Bool, isNewline: Bool) {
                let count = end - start
                guard count > 0 else {
                    if isNewline { preparedText.append(width: 0, isSpace: true, isNewline: true, height: lineHeight) }
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
                        preparedText.append(width: width, isSpace: isSpace, isNewline: false, height: lineHeight)
                    } else {
                        preparedText.append(width: 0, isSpace: isSpace, isNewline: false, height: lineHeight)
                    }
                }
                
                if isNewline {
                    preparedText.append(width: 0, isSpace: true, isNewline: true, height: lineHeight)
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
                    measureSegment(from: segmentStartIndex, to: i, isSpace: isCurrentSpace, isNewline: true)
                    segmentStartIndex = i + 1
                    isCurrentSpace = false // Reset after newline
                } else if isSpaceChar != isCurrentSpace {
                    if i > segmentStartIndex {
                        measureSegment(from: segmentStartIndex, to: i, isSpace: isCurrentSpace, isNewline: false)
                    }
                    segmentStartIndex = i
                    isCurrentSpace = isSpaceChar
                }
            }
            
            // Final segment in range
            if segmentStartIndex < range.location + range.length {
                measureSegment(from: segmentStartIndex, to: range.location + range.length, isSpace: isCurrentSpace, isNewline: false)
            }
        }
        
        return preparedText
    }
}
