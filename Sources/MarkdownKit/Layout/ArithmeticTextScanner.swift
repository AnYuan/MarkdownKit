//
//  ArithmeticTextScanner.swift
//  MarkdownKit
//

import Foundation

struct ArithmeticTextScanner: IteratorProtocol {

    enum SpanKind {
        case text
        case space
        case softHyphen
        case hardBreak
    }

    struct Span {
        let kind: SpanKind
        let range: NSRange
    }

    private let utf16: [unichar]
    private let rangeEnd: Int
    private var index: Int
    private var segmentStart: Int
    private var currentSegmentIsSpace = false
    private var pendingMarker: Span?

    init(utf16: [unichar], range: NSRange) {
        self.utf16 = utf16
        self.rangeEnd = NSMaxRange(range)
        self.index = range.location
        self.segmentStart = range.location
    }

    mutating func next() -> Span? {
        if let pendingMarker {
            self.pendingMarker = nil
            return pendingMarker
        }

        while index < rangeEnd {
            let character = utf16[index]

            if character == 0x00AD {
                let marker = Span(
                    kind: .softHyphen,
                    range: NSRange(location: index, length: 1)
                )
                if segmentStart < index {
                    let span = currentSpan(endingAt: index)
                    advancePastMarker()
                    pendingMarker = marker
                    return span
                }
                advancePastMarker()
                return marker
            } else if let hardBreakLength = Self.hardBreakLength(utf16: utf16, index: index, rangeEnd: rangeEnd) {
                let marker = Span(
                    kind: .hardBreak,
                    range: NSRange(location: index, length: hardBreakLength)
                )
                if segmentStart < index {
                    let span = currentSpan(endingAt: index)
                    advancePastMarker(length: hardBreakLength)
                    pendingMarker = marker
                    return span
                }
                advancePastMarker(length: hardBreakLength)
                return marker
            } else {
                let isSpace = Self.isBreakableSpace(character)
                if isSpace != currentSegmentIsSpace {
                    if segmentStart < index {
                        let span = currentSpan(endingAt: index)
                        segmentStart = index
                        currentSegmentIsSpace = isSpace
                        return span
                    }
                    segmentStart = index
                    currentSegmentIsSpace = isSpace
                }
                index += 1
            }
        }

        guard segmentStart < rangeEnd else { return nil }
        let span = currentSpan(endingAt: rangeEnd)
        segmentStart = rangeEnd
        return span
    }

    private func currentSpan(endingAt end: Int) -> Span {
        Span(
            kind: currentSegmentIsSpace ? .space : .text,
            range: NSRange(location: segmentStart, length: end - segmentStart)
        )
    }

    private mutating func advancePastMarker() {
        advancePastMarker(length: 1)
    }

    private mutating func advancePastMarker(length: Int) {
        index += length
        segmentStart = index
        currentSegmentIsSpace = false
    }

    private static func hardBreakLength(utf16: [unichar], index: Int, rangeEnd: Int) -> Int? {
        switch utf16[index] {
        case 0x000D:
            if index + 1 < rangeEnd, utf16[index + 1] == 0x000A {
                return 2
            }
            return 1
        case 0x000A, 0x2028, 0x2029:
            return 1
        default:
            return nil
        }
    }

    private static func isBreakableSpace(_ character: unichar) -> Bool {
        character == 0x0020 || character == 0x0009 || character == 0x200B
    }
}
