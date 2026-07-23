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
        guard textRange.length > 1 else { return [textRange] }

        let rangeIsASCII = isASCII(textRange, utf16: utf16)
        if rangeIsASCII,
           isSingleASCIIToken(textRange, utf16: utf16) {
            return [textRange]
        }
        if rangeIsASCII,
           isASCIINumericStickyToken(textRange, utf16: utf16) {
            return [textRange]
        }

        let wordRanges: [NSRange]
        if rangeIsASCII,
           isSimpleASCIIHyphenatedToken(textRange, utf16: utf16) {
            wordRanges = asciiWordRanges(in: textRange, utf16: utf16)
        } else {
            var localizedRanges: [NSRange] = []
            fullString.enumerateSubstrings(
                in: textRange,
                options: [.byWords, .substringNotRequired, .localized]
            ) { _, substringRange, _, _ in
                let clampedRange = NSIntersectionRange(textRange, substringRange)
                if clampedRange.length > 0 {
                    localizedRanges.append(clampedRange)
                }
            }
            wordRanges = localizedRanges
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

    private static func isSingleASCIIToken(
        _ range: NSRange,
        utf16: [unichar]
    ) -> Bool {
        let end = NSMaxRange(range)
        var index = range.location
        var sawWordCharacter = false
        var pureWord = true
        var containsLetter = false
        var containsDigit = false
        var containsUnderscore = false
        var containsApostrophe = false
        var containsQuestionMark = false

        while index < end {
            let character = utf16[index]
            switch character {
            case 0x30...0x39:
                containsDigit = true
            case 0x41...0x5A, 0x61...0x7A:
                containsLetter = true
            case 0x5F:
                containsUnderscore = true
            case 0x27:
                containsApostrophe = true
            case 0x3F:
                containsQuestionMark = true
            default:
                break
            }

            if isASCIIWordCharacter(character) {
                sawWordCharacter = true
            } else if character == 0x27,
                      index > range.location,
                      index + 1 < end,
                      isASCIIApostropheBridge(
                        utf16[index - 1],
                        utf16[index + 1]
                      ) {
                // Foundation treats an in-word apostrophe as part of the word.
            } else {
                pureWord = false
            }
            index += 1
        }

        if pureWord, !(containsUnderscore && containsApostrophe) {
            return true
        }
        if !sawWordCharacter {
            return true
        }

        // A word followed only by closing punctuation is merged back into one
        // token by the general path, so avoid constructing three temporary arrays.
        index = range.location
        while index < end, isASCIIWordCharacter(utf16[index]) {
            index += 1
        }
        if index > range.location, index < end {
            var suffixIsClosingPunctuation = true
            for suffixIndex in index..<end
            where !isASCIIClosingPunctuation(utf16[suffixIndex]) {
                suffixIsClosingPunctuation = false
                break
            }
            if suffixIsClosingPunctuation,
               !(containsQuestionMark && containsLetter && containsDigit) {
                return true
            }
        }

        return false
    }

    private static func isASCIIClosingPunctuation(_ character: unichar) -> Bool {
        switch character {
        case 0x21, 0x22, 0x25, 0x27, 0x29, 0x2C, 0x2E, 0x3A...0x3B,
             0x3F, 0x5D, 0x7D:
            return true
        default:
            return false
        }
    }

    private static func isASCIINumericStickyToken(
        _ range: NSRange,
        utf16: [unichar]
    ) -> Bool {
        var containsDigit = false
        for index in range.location..<NSMaxRange(range) {
            switch utf16[index] {
            case 0x30...0x39:
                containsDigit = true
            case 0x23, 0x28...0x29, 0x2B...0x2F, 0x3A:
                continue
            default:
                return false
            }
        }
        return containsDigit
    }

    private static func isSimpleASCIIHyphenatedToken(
        _ range: NSRange,
        utf16: [unichar]
    ) -> Bool {
        var containsHyphen = false
        for index in range.location..<NSMaxRange(range) {
            switch utf16[index] {
            case 0x2D:
                containsHyphen = true
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                continue
            default:
                return false
            }
        }
        return containsHyphen
    }

    /// Foundation's localized word enumeration is retained for non-ASCII text
    /// (Thai dictionary boundaries in particular) and complex ASCII punctuation.
    /// Builder-heavy list and quote output is overwhelmingly simple ASCII, where
    /// deterministic fast paths avoid initializing a linguistic tokenizer once
    /// per attributed run without changing its boundary semantics.
    private static func isASCII(_ range: NSRange, utf16: [unichar]) -> Bool {
        for index in range.location..<NSMaxRange(range) where utf16[index] > 0x7F {
            return false
        }
        return true
    }

    private static func asciiWordRanges(in range: NSRange, utf16: [unichar]) -> [NSRange] {
        let end = NSMaxRange(range)
        var result: [NSRange] = []
        result.reserveCapacity(max(1, range.length / 6))
        var index = range.location

        while index < end {
            guard isASCIIAlphaNumeric(utf16[index]) else {
                index += 1
                continue
            }

            let start = index
            index += 1
            while index < end {
                let character = utf16[index]
                if isASCIIAlphaNumeric(character) {
                    index += 1
                    continue
                }
                break
            }
            result.append(NSRange(location: start, length: index - start))
        }

        return result
    }

    private static func isASCIIAlphaNumeric(_ character: unichar) -> Bool {
        switch character {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    private static func isASCIIWordCharacter(_ character: unichar) -> Bool {
        switch character {
        case 0x30...0x39, 0x41...0x5A, 0x5F, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    private static func asciiWordClass(_ character: unichar) -> UInt8? {
        switch character {
        case 0x41...0x5A, 0x61...0x7A:
            return 1
        case 0x30...0x39:
            return 2
        case 0x5F:
            return 3
        default:
            return nil
        }
    }

    private static func isASCIIApostropheBridge(
        _ left: unichar,
        _ right: unichar
    ) -> Bool {
        guard let leftClass = asciiWordClass(left) else { return false }
        return asciiWordClass(right) == leftClass
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

        // UAX #14 treats ASCII hyphen-minus as a break-after character: it
        // stays painted with the word on its left, while the following word may
        // move to the next line. Keeping `-` as its own token incorrectly made
        // `prefix-width` break as `prefix` / `-width`.
        if isASCIIHyphenToken(rightText) {
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

    private static func isASCIIHyphenToken(_ text: String) -> Bool {
        text == "-"
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
