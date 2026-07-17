//
//  ArithmeticTextSegmentClassifierMerger.swift
//  MarkdownKit
//

import Foundation

struct ArithmeticTextSegmentClassifierMerger {

    private static let alphanumerics = CharacterSet.alphanumerics
    private static let decimalDigits = CharacterSet.decimalDigits
    private static let urlPunctuation = CharacterSet(charactersIn: "-._~:/?#[]@!$&'()*+,;=%")
    private static let numericPunctuation = CharacterSet(charactersIn: "-/:.,+()#")
    private static let cjkPunctuation = CharacterSet(charactersIn: "，。！？：；、（）《》「」『』【】〈〉〔〕［］｛｝—…·・")
    private static let closingPunctuation = CharacterSet(charactersIn: ".,;:!?%)]}'\"”’")

    static func classifyAndMerge(
        textRange: NSRange,
        in fullString: NSString,
        utf16: [unichar]
    ) -> [NSRange] {
        guard textRange.length > 0 else { return [] }

        var wordRanges: [NSRange] = []
        fullString.enumerateSubstrings(
            in: textRange,
            options: [.byWords, .substringNotRequired, .localized]
        ) { _, substringRange, _, _ in
            let clampedRange = NSIntersectionRange(textRange, substringRange)
            if clampedRange.length > 0 {
                wordRanges.append(clampedRange)
            }
        }

        guard !wordRanges.isEmpty else {
            return [textRange]
        }

        var tokenRanges: [NSRange] = []
        var currentTokenRange = wordRanges[0]

        for wordRange in wordRanges.dropFirst() {
            let gapStart = NSMaxRange(currentTokenRange)
            let gapEnd = wordRange.location

            if isGlueOnlyRange(from: gapStart, to: gapEnd, utf16: utf16) {
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

        if let firstTokenRange = tokenRanges.first, textRange.location < firstTokenRange.location {
            tokenRanges.insert(
                NSRange(location: textRange.location, length: firstTokenRange.location - textRange.location),
                at: 0
            )
        }

        if let lastTokenRange = tokenRanges.last {
            let lastTokenEnd = NSMaxRange(lastTokenRange)
            if lastTokenEnd < NSMaxRange(textRange) {
                tokenRanges.append(
                    NSRange(location: lastTokenEnd, length: NSMaxRange(textRange) - lastTokenEnd)
                )
            }
        }

        var mergedTokenRanges: [NSRange] = []
        for tokenRange in tokenRanges {
            guard let lastRange = mergedTokenRanges.last else {
                mergedTokenRanges.append(tokenRange)
                continue
            }

            if NSMaxRange(lastRange) == tokenRange.location,
               shouldMergeAdjacentTextTokens(left: lastRange, right: tokenRange, in: fullString) {
                mergedTokenRanges[mergedTokenRanges.count - 1] = NSRange(
                    location: lastRange.location,
                    length: NSMaxRange(tokenRange) - lastRange.location
                )
            } else {
                mergedTokenRanges.append(tokenRange)
            }
        }

        return mergedTokenRanges
    }

    private static func isGlueOnlyRange(from start: Int, to end: Int, utf16: [unichar]) -> Bool {
        guard start < end else { return false }
        for index in start..<end where !isGlueCharacter(utf16[index]) {
            return false
        }
        return true
    }

    private static func isGlueCharacter(_ character: unichar) -> Bool {
        character == 0x00A0 || character == 0x202F || character == 0x2060
    }

    private static func shouldMergeAdjacentTextTokens(left: NSRange, right: NSRange, in fullString: NSString) -> Bool {
        let leftText = fullString.substring(with: left)
        let rightText = fullString.substring(with: right)

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

    private static func isURLSafeToken(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            alphanumerics.contains(scalar) || urlPunctuation.contains(scalar)
        }
    }

    private static func isURLLikeToken(_ text: String) -> Bool {
        guard isURLSafeToken(text) else { return false }
        return text.contains("://")
            || text.contains(".")
            || text.contains("@")
            || text.contains("/")
            || text.contains("?")
            || text.contains("#")
    }

    private static func isClosingPunctuationToken(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy(closingPunctuation.contains)
    }

    private static func isNumericStickyToken(_ text: String) -> Bool {
        !text.isEmpty
            && text.unicodeScalars.contains(where: decimalDigits.contains)
            && text.unicodeScalars.allSatisfy { scalar in
                decimalDigits.contains(scalar) || numericPunctuation.contains(scalar)
            }
    }

    private static func isCJKStickyToken(_ text: String) -> Bool {
        !text.isEmpty
            && text.unicodeScalars.contains(where: isCJKScalar)
            && text.unicodeScalars.allSatisfy { scalar in
                isCJKScalar(scalar) || decimalDigits.contains(scalar) || cjkPunctuation.contains(scalar)
            }
    }

    private static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
