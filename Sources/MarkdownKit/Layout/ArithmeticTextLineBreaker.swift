//
//  ArithmeticTextLineBreaker.swift
//  MarkdownKit
//

import Foundation
import CoreText

struct ArithmeticTextLineBreaker {

    private struct State {
        var currentLineAdvance: CGFloat = 0
        var currentLineFitWidth: CGFloat = 0
        var currentLinePaintWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxComputedWidth: CGFloat = 0
        var lineCount = 0
    }

    static func layout(
        prepared preparedText: ArithmeticTextCalculator.PreparedText,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        guard !preparedText.widths.isEmpty else { return .zero }

        var state = State()

        for chunk in preparedText.chunks {
            let index = chunk.segmentIndex
            let width = preparedText.widths[index]
            let lineEndFitAdvance = preparedText.lineEndFitAdvances[index]
            let lineEndPaintAdvance = preparedText.lineEndPaintAdvances[index]
            let segmentText = preparedText.segmentTexts[index]
            let ctFont = preparedText.ctFonts[index]
            let kind = preparedText.kinds[index]
            let height = preparedText.heights[index]
            let currentIndent = state.lineCount == 0 ? preparedText.firstLineHeadIndent : preparedText.headIndent
            let availableWidth = maxWidth - currentIndent

            if chunk.kind == .hardBreak {
                state.totalHeight += max(state.currentLineHeight, height)
                let committedPaintWidth = committedLinePaintWidth(state, availableWidth: availableWidth)
                let visibleLineWidth = committedPaintWidth > 0 ? committedPaintWidth + currentIndent : 0
                state.maxComputedWidth = max(state.maxComputedWidth, visibleLineWidth)
                state.currentLineAdvance = 0
                state.currentLineFitWidth = 0
                state.currentLinePaintWidth = 0
                state.currentLineHeight = 0
                state.lineCount += 1
                continue
            }

            let nextLineAdvance = state.currentLineAdvance + width
            let nextLineFitWidth = state.currentLineAdvance + lineEndFitAdvance
            let nextLinePaintWidth = state.currentLineAdvance + lineEndPaintAdvance

            if nextLineFitWidth > availableWidth && state.currentLineAdvance > 0 {
                state.totalHeight += state.currentLineHeight
                let committedPaintWidth = committedLinePaintWidth(state, availableWidth: availableWidth)
                state.maxComputedWidth = max(state.maxComputedWidth, committedPaintWidth + currentIndent)

                state.lineCount += 1
                if kind.isSpace {
                    state.currentLineAdvance = 0
                    state.currentLineFitWidth = 0
                    state.currentLinePaintWidth = 0
                    state.currentLineHeight = 0
                } else {
                    let nextIndent = state.lineCount == 0 ? preparedText.firstLineHeadIndent : preparedText.headIndent
                    let nextAvailableWidth = maxWidth - nextIndent
                    if let ctFont, kind == .text && width > nextAvailableWidth && !segmentText.isEmpty {
                        state.currentLineAdvance = 0
                        state.currentLineFitWidth = 0
                        state.currentLinePaintWidth = 0
                        state.currentLineHeight = 0
                        appendOversizedTextSegment(
                            text: segmentText,
                            ctFont: ctFont,
                            height: height,
                            preparedText: preparedText,
                            maxWidth: maxWidth,
                            state: &state
                        )
                    } else {
                        state.currentLineAdvance = width
                        state.currentLineFitWidth = lineEndFitAdvance
                        state.currentLinePaintWidth = lineEndPaintAdvance
                        state.currentLineHeight = height
                    }
                }
            } else if let ctFont, nextLineFitWidth > availableWidth, kind == .text, !segmentText.isEmpty {
                appendOversizedTextSegment(
                    text: segmentText,
                    ctFont: ctFont,
                    height: height,
                    preparedText: preparedText,
                    maxWidth: maxWidth,
                    state: &state
                )
            } else {
                state.currentLineAdvance = nextLineAdvance
                state.currentLineFitWidth = nextLineFitWidth
                state.currentLinePaintWidth = nextLinePaintWidth
                state.currentLineHeight = max(state.currentLineHeight, height)
            }
        }

        if state.currentLineAdvance > 0 || state.totalHeight == 0 {
            let currentIndent = state.lineCount == 0 ? preparedText.firstLineHeadIndent : preparedText.headIndent
            let availableWidth = maxWidth - currentIndent
            state.totalHeight += state.currentLineHeight
            let committedPaintWidth = committedLinePaintWidth(state, availableWidth: availableWidth)
            let visibleLineWidth = committedPaintWidth > 0 ? committedPaintWidth + currentIndent : 0
            state.maxComputedWidth = max(state.maxComputedWidth, visibleLineWidth)
        }

        return CGSize(width: ceil(state.maxComputedWidth), height: floor(state.totalHeight))
    }

    // TextKit retains fitting trailing separators, but clips their overhang at the line fragment.
    private static func committedLinePaintWidth(_ state: State, availableWidth: CGFloat) -> CGFloat {
        guard state.currentLinePaintWidth > state.currentLineFitWidth else {
            return state.currentLinePaintWidth
        }
        return min(state.currentLinePaintWidth, max(availableWidth, state.currentLineFitWidth))
    }

    private static func appendOversizedTextSegment(
        text: String,
        ctFont: CTFont,
        height: CGFloat,
        preparedText: ArithmeticTextCalculator.PreparedText,
        maxWidth: CGFloat,
        state: inout State
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributedText)
        let nsText = text as NSString
        var start = 0

        while start < nsText.length {
            let currentIndent = state.lineCount == 0 ? preparedText.firstLineHeadIndent : preparedText.headIndent
            let availableWidth = max(maxWidth - currentIndent, 0)
            var count = CTTypesetterSuggestClusterBreak(typesetter, start, Double(availableWidth))

            if count <= 0 {
                count = nsText.rangeOfComposedCharacterSequence(at: start).length
            }

            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

            state.currentLineAdvance = lineWidth
            state.currentLineFitWidth = lineWidth
            state.currentLinePaintWidth = lineWidth
            state.currentLineHeight = max(state.currentLineHeight, height)
            start += count

            if start < nsText.length {
                state.totalHeight += state.currentLineHeight
                state.maxComputedWidth = max(state.maxComputedWidth, state.currentLinePaintWidth + currentIndent)
                state.lineCount += 1
                state.currentLineAdvance = 0
                state.currentLineFitWidth = 0
                state.currentLinePaintWidth = 0
                state.currentLineHeight = 0
            }
        }
    }
}
