//
//  ArithmeticTextLineBreaker.swift
//  MarkdownKit
//

import Foundation
import CoreText

struct ArithmeticTextLineBreaker {

    /// Keeps arithmetic geometry inside a finite Core Graphics coordinate range.
    /// Values above this point are not meaningful display dimensions and can
    /// otherwise overflow while paragraph spacing and line heights accumulate.
    private static let maximumLayoutDimension = CGFloat(Int32.max)

    private struct LayoutState {
        var totalHeight: CGFloat = 0
        var minComputedX: CGFloat?
        var maxComputedX: CGFloat?
        var minComputedY: CGFloat?
        var maxComputedY: CGFloat?
    }

    private struct LineState {
        var currentLineAdvance: CGFloat = 0
        var currentLineFitWidth: CGFloat = 0
        var currentLinePaintWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var pendingDiscretionaryHyphenWidth: CGFloat?
        var lineCount = 0
    }

    static func layout(
        prepared preparedText: ArithmeticTextCalculator.PreparedText,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        guard !preparedText.chunks.isEmpty || !preparedText.paragraphs.isEmpty else { return .zero }

        let constrainedWidth = boundedLayoutDimension(maxWidth)

        let paragraphs = preparedText.paragraphs.isEmpty
            ? [
                ArithmeticTextCalculator.Paragraph(
                    chunkRange: 0..<preparedText.chunks.count,
                    firstLineHeadIndent: preparedText.firstLineHeadIndent,
                    headIndent: preparedText.headIndent,
                    paragraphSpacingBefore: 0,
                    paragraphSpacingAfter: 0,
                    emptyLineHeight: 0
                )
            ]
            : preparedText.paragraphs

        var layoutState = LayoutState()

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            layoutParagraph(
                paragraph,
                isFirstParagraph: paragraphIndex == 0,
                addsTerminalLine: paragraphIndex == paragraphs.count - 1
                    && paragraphEndsInHardBreak(paragraph, preparedText: preparedText),
                preparedText: preparedText,
                constrainedToWidth: constrainedWidth,
                layoutState: &layoutState
            )
        }

        let computedWidth: CGFloat
        if let minComputedX = layoutState.minComputedX,
           let maxComputedX = layoutState.maxComputedX {
            computedWidth = max(0, maxComputedX - minComputedX)
        } else {
            computedWidth = 0
        }
        let computedHeight: CGFloat
        if let minComputedY = layoutState.minComputedY,
           let maxComputedY = layoutState.maxComputedY {
            computedHeight = max(0, maxComputedY - minComputedY)
        } else {
            computedHeight = 0
        }
        return CGSize(width: ceil(computedWidth), height: ceil(computedHeight))
    }

    private static func layoutParagraph(
        _ rawParagraph: ArithmeticTextCalculator.Paragraph,
        isFirstParagraph: Bool,
        addsTerminalLine: Bool,
        preparedText: ArithmeticTextCalculator.PreparedText,
        constrainedToWidth maxWidth: CGFloat,
        layoutState: inout LayoutState
    ) {
        let paragraph = ArithmeticTextCalculator.Paragraph(
            chunkRange: rawParagraph.chunkRange,
            firstLineHeadIndent: boundedLayoutDimension(rawParagraph.firstLineHeadIndent),
            headIndent: boundedLayoutDimension(rawParagraph.headIndent),
            paragraphSpacingBefore: rawParagraph.paragraphSpacingBefore,
            paragraphSpacingAfter: rawParagraph.paragraphSpacingAfter,
            emptyLineHeight: rawParagraph.emptyLineHeight
        )

        if !isFirstParagraph {
            layoutState.totalHeight = addingLayoutDimensions(
                layoutState.totalHeight,
                paragraph.paragraphSpacingBefore
            )
        }

        guard !paragraph.chunkRange.isEmpty else {
            let lineStartY = layoutState.totalHeight
            layoutState.totalHeight = addingLayoutDimensions(
                layoutState.totalHeight,
                paragraph.emptyLineHeight
            )
            recordUsedRect(
                x: paragraph.firstLineHeadIndent,
                width: 0,
                minY: lineStartY,
                maxY: layoutState.totalHeight,
                layoutState: &layoutState
            )
            layoutState.totalHeight = addingLayoutDimensions(
                layoutState.totalHeight,
                paragraph.paragraphSpacingAfter
            )
            return
        }

        var lineState = LineState()

        for chunkIndex in paragraph.chunkRange {
            let chunk = preparedText.chunks[chunkIndex]
            let index = chunk.segmentIndex
            let width = preparedText.widths[index]
            let lineEndFitAdvance = preparedText.lineEndFitAdvances[index]
            let lineEndPaintAdvance = preparedText.lineEndPaintAdvances[index]
            let segmentText = preparedText.segmentTexts[index]
            let ctFont = preparedText.ctFonts[index]
            let kind = preparedText.kinds[index]
            let height = preparedText.heights[index]
            let currentIndent = indent(for: lineState.lineCount, in: paragraph)
            let availableWidth = maxWidth - currentIndent

            if chunk.kind == .hardBreak {
                let contributesToUsedRect = lineState.currentLineHeight == 0 || availableWidth > 0
                commitCurrentLine(
                    paragraph: paragraph,
                    lineHeightFallback: lineState.currentLineHeight > 0 ? 0 : height,
                    constrainedToWidth: maxWidth,
                    layoutState: &layoutState,
                    lineState: &lineState,
                    contributesToUsedRect: contributesToUsedRect
                )
                continue
            }

            if kind == .softHyphen {
                lineState.pendingDiscretionaryHyphenWidth =
                    lineState.currentLineAdvance + lineEndPaintAdvance
                lineState.currentLineHeight = max(lineState.currentLineHeight, height)
                continue
            }

            let nextLineAdvance = lineState.currentLineAdvance + width
            let nextLineFitWidth = lineState.currentLineAdvance + lineEndFitAdvance
            let nextLinePaintWidth = lineState.currentLineAdvance + lineEndPaintAdvance

            if nextLineFitWidth > availableWidth && lineState.currentLineAdvance > 0 {
                commitCurrentLine(
                    paragraph: paragraph,
                    lineHeightFallback: lineState.currentLineHeight,
                    constrainedToWidth: maxWidth,
                    layoutState: &layoutState,
                    lineState: &lineState,
                    showsDiscretionaryHyphen: true,
                    contributesToUsedRect: availableWidth > 0
                )

                if kind.isSpace {
                    continue
                }

                let nextIndent = indent(for: lineState.lineCount, in: paragraph)
                let nextAvailableWidth = maxWidth - nextIndent
                if let ctFont, kind == .text, width > nextAvailableWidth, !segmentText.isEmpty {
                    appendOversizedTextSegment(
                        text: segmentText,
                        ctFont: ctFont,
                        height: height,
                        paragraph: paragraph,
                        maxWidth: maxWidth,
                        layoutState: &layoutState,
                        lineState: &lineState
                    )
                } else {
                    lineState.currentLineAdvance = width
                    lineState.currentLineFitWidth = lineEndFitAdvance
                    lineState.currentLinePaintWidth = lineEndPaintAdvance
                    lineState.currentLineHeight = height
                }
            } else if let ctFont, nextLineFitWidth > availableWidth, kind == .text, !segmentText.isEmpty {
                lineState.pendingDiscretionaryHyphenWidth = nil
                appendOversizedTextSegment(
                    text: segmentText,
                    ctFont: ctFont,
                    height: height,
                    paragraph: paragraph,
                    maxWidth: maxWidth,
                    layoutState: &layoutState,
                    lineState: &lineState
                )
            } else {
                lineState.currentLineAdvance = nextLineAdvance
                lineState.currentLineFitWidth = nextLineFitWidth
                lineState.currentLinePaintWidth = nextLinePaintWidth
                lineState.currentLineHeight = max(lineState.currentLineHeight, height)
                lineState.pendingDiscretionaryHyphenWidth = nil
            }
        }

        if lineState.currentLineHeight > 0 {
            let currentIndent = indent(for: lineState.lineCount, in: paragraph)
            commitCurrentLine(
                paragraph: paragraph,
                lineHeightFallback: lineState.currentLineHeight,
                constrainedToWidth: maxWidth,
                layoutState: &layoutState,
                lineState: &lineState,
                contributesToUsedRect: maxWidth - currentIndent > 0
            )
        }

        if addsTerminalLine,
           let finalChunkIndex = paragraph.chunkRange.last {
            let finalChunk = preparedText.chunks[finalChunkIndex]
            commitCurrentLine(
                paragraph: paragraph,
                lineHeightFallback: preparedText.heights[finalChunk.segmentIndex],
                constrainedToWidth: maxWidth,
                layoutState: &layoutState,
                lineState: &lineState,
                contributesToUsedRect: true
            )
        }

        layoutState.totalHeight = addingLayoutDimensions(
            layoutState.totalHeight,
            paragraph.paragraphSpacingAfter
        )
    }

    private static func paragraphEndsInHardBreak(
        _ paragraph: ArithmeticTextCalculator.Paragraph,
        preparedText: ArithmeticTextCalculator.PreparedText
    ) -> Bool {
        guard let finalChunkIndex = paragraph.chunkRange.last else { return false }
        return preparedText.chunks[finalChunkIndex].kind == .hardBreak
    }

    // TextKit retains fitting trailing separators, but clips all paint at the line fragment.
    private static func committedLinePaintWidth(
        _ state: LineState,
        availableWidth: CGFloat,
        showsDiscretionaryHyphen: Bool
    ) -> CGFloat {
        let clippedAvailableWidth = max(availableWidth, 0)
        var paintWidth = state.currentLinePaintWidth
        if showsDiscretionaryHyphen,
           let discretionaryWidth = state.pendingDiscretionaryHyphenWidth,
           discretionaryWidth <= clippedAvailableWidth {
            paintWidth = max(paintWidth, discretionaryWidth)
        }
        return min(max(paintWidth, 0), clippedAvailableWidth)
    }

    private static func indent(
        for lineCount: Int,
        in paragraph: ArithmeticTextCalculator.Paragraph
    ) -> CGFloat {
        lineCount == 0 ? paragraph.firstLineHeadIndent : paragraph.headIndent
    }

    private static func commitCurrentLine(
        paragraph: ArithmeticTextCalculator.Paragraph,
        lineHeightFallback: CGFloat,
        constrainedToWidth maxWidth: CGFloat,
        layoutState: inout LayoutState,
        lineState: inout LineState,
        showsDiscretionaryHyphen: Bool = false,
        contributesToUsedRect: Bool = true
    ) {
        let currentIndent = indent(for: lineState.lineCount, in: paragraph)
        let availableWidth = maxWidth - currentIndent
        let lineStartY = layoutState.totalHeight
        layoutState.totalHeight = addingLayoutDimensions(
            layoutState.totalHeight,
            max(lineState.currentLineHeight, lineHeightFallback)
        )
        if contributesToUsedRect {
            let committedPaintWidth = committedLinePaintWidth(
                lineState,
                availableWidth: availableWidth,
                showsDiscretionaryHyphen: showsDiscretionaryHyphen
            )
            recordUsedRect(
                x: currentIndent,
                width: committedPaintWidth,
                minY: lineStartY,
                maxY: layoutState.totalHeight,
                layoutState: &layoutState
            )
        }
        lineState.currentLineAdvance = 0
        lineState.currentLineFitWidth = 0
        lineState.currentLinePaintWidth = 0
        lineState.currentLineHeight = 0
        lineState.pendingDiscretionaryHyphenWidth = nil
        lineState.lineCount += 1
    }

    private static func recordUsedRect(
        x: CGFloat,
        width: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        layoutState: inout LayoutState
    ) {
        let boundedX = boundedLayoutDimension(x)
        let boundedWidth = boundedLayoutDimension(width)
        let boundedMinY = boundedLayoutDimension(minY)
        let boundedMaxY = boundedLayoutDimension(maxY)
        let maxX = addingLayoutDimensions(boundedX, boundedWidth)
        layoutState.minComputedX = min(layoutState.minComputedX ?? boundedX, boundedX)
        layoutState.maxComputedX = max(layoutState.maxComputedX ?? maxX, maxX)
        layoutState.minComputedY = min(layoutState.minComputedY ?? boundedMinY, boundedMinY)
        layoutState.maxComputedY = max(layoutState.maxComputedY ?? boundedMaxY, boundedMaxY)
    }

    private static func boundedLayoutDimension(_ value: CGFloat) -> CGFloat {
        guard value > 0 else { return 0 }
        guard value < maximumLayoutDimension else { return maximumLayoutDimension }
        return value
    }

    private static func addingLayoutDimensions(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let boundedLHS = boundedLayoutDimension(lhs)
        let boundedRHS = boundedLayoutDimension(rhs)
        guard boundedLHS < maximumLayoutDimension - boundedRHS else {
            return maximumLayoutDimension
        }
        return boundedLHS + boundedRHS
    }

    private static func appendOversizedTextSegment(
        text: String,
        ctFont: CTFont,
        height: CGFloat,
        paragraph: ArithmeticTextCalculator.Paragraph,
        maxWidth: CGFloat,
        layoutState: inout LayoutState,
        lineState: inout LineState
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
        let nsText = text as NSString
        var start = 0

        while start < nsText.length {
            let currentIndent = indent(for: lineState.lineCount, in: paragraph)
            let availableWidth = max(maxWidth - currentIndent, 0)
            var count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(availableWidth))

            if count <= 0 {
                count = nsText.rangeOfComposedCharacterSequence(at: start).length
            }

            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

            lineState.currentLineAdvance = lineWidth
            lineState.currentLineFitWidth = lineWidth
            lineState.currentLinePaintWidth = lineWidth
            lineState.currentLineHeight = max(lineState.currentLineHeight, height)
            start += count

            if start < nsText.length {
                commitCurrentLine(
                    paragraph: paragraph,
                    lineHeightFallback: height,
                    constrainedToWidth: maxWidth,
                    layoutState: &layoutState,
                    lineState: &lineState,
                    contributesToUsedRect: availableWidth > 0
                )
            }
        }
    }
}
