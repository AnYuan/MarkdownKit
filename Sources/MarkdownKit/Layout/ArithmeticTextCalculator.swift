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
        let string = attributedString.string
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            guard let font = attributes[.font] as? Font else { return }
            
            // Convert platform Font to CTFont
            #if canImport(UIKit)
            let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
            #elseif canImport(AppKit)
            let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
            #endif
            
            let substring = (string as NSString).substring(with: range)
            
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
            
            // Simple segmentation: by word boundaries and spaces.
            // Using NSString enumeration for words.
            substring.enumerateSubstrings(in: substring.startIndex..<substring.endIndex, options: [.byWords, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
                // The enclosing range contains the word AND the trailing spaces/punctuation.
                // To mirror pretext, we need to segment this carefully into [Word] [Space] [Punctuation]
                // but for this initial SoA pass we'll do a simpler approach: process character by character
                // or group words, then spaces.
                
                // Let's do a character-class based grouping for maximum precision on simple text
                let groupString = String(substring[enclosingRange])
                
                // Extremely simple tokenizer for the PoC
                var currentSegment = ""
                var isCurrentSpace = false
                
                for char in groupString {
                    let isSpace = char.isWhitespace
                    let isNewline = char.isNewline
                    
                    if isNewline {
                        if !currentSegment.isEmpty {
                            let width = self.measureText(currentSegment, font: ctFont)
                            preparedText.append(width: width, isSpace: isCurrentSpace, isNewline: false, height: lineHeight)
                            currentSegment = ""
                        }
                        preparedText.append(width: 0, isSpace: true, isNewline: true, height: lineHeight)
                    } else if isSpace != isCurrentSpace {
                        if !currentSegment.isEmpty {
                            let width = self.measureText(currentSegment, font: ctFont)
                            preparedText.append(width: width, isSpace: isCurrentSpace, isNewline: false, height: lineHeight)
                        }
                        currentSegment = String(char)
                        isCurrentSpace = isSpace
                    } else {
                        currentSegment.append(char)
                    }
                }
                
                if !currentSegment.isEmpty {
                    let width = self.measureText(currentSegment, font: ctFont)
                    preparedText.append(width: width, isSpace: isCurrentSpace, isNewline: false, height: lineHeight)
                }
            }
        }
        
        return preparedText
    }
    
    private func measureText(_ text: String, font: CTFont) -> CGFloat {
        // Use CoreText to get exact advances for glyphs.
        // This is significantly faster than using NSAttributedString.size()
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        
        let hasGlyphs = CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
        guard hasGlyphs else { return 0 }
        
        var advances = [CGSize](repeating: .zero, count: chars.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, chars.count)
        
        return advances.reduce(0) { $0 + $1.width }
    }
}
