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

    /// NSCache is internally thread-safe; its soft count limit bounds the shared width cache.
    private static nonisolated(unsafe) let cachedWidths: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 50_000
        return cache
    }()

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
        let key = "\(fontKey.fontName)|\(fontKey.pointSizeMilli)|\(text)" as NSString
        return cachedWidths.object(forKey: key).map { CGFloat(truncating: $0) }
    }

    private static func storeCachedWidth(_ width: CGFloat, for text: String, fontKey: FontCacheKey) {
        let key = "\(fontKey.fontName)|\(fontKey.pointSizeMilli)|\(text)" as NSString
        cachedWidths.setObject(NSNumber(value: Double(width)), forKey: key)
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
