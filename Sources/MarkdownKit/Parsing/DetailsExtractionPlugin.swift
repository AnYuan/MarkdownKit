import Foundation
import Markdown

/// An ASTPlugin that upgrades raw HTML details tags into dedicated AST nodes.
///
/// Supported structure:
/// `<details [open]>`
/// `<summary>...</summary>` or `<summary>` ... `</summary>`
/// `...body markdown...`
/// `</details>`
public struct DetailsExtractionPlugin: ASTPlugin {
    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        // The 24-case per-container `switch` previously here is replaced by
        // `AST.transform`, which handles recursion and identity preservation.
        // The Details-specific work — splitting multi-line HTML tags into
        // separate nodes, then matching opener/closer pairs — runs as
        // `postProcessSiblings` so it fires at every container level.
        AST.transform(
            nodes,
            postProcessSiblings: { siblings in
                mergeDetails(in: expandDetailsHTMLTagNodes(in: siblings))
            },
            visit: { _ in .unchanged }
        )
    }

    private func mergeDetails(in nodes: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        var index = 0

        while index < nodes.count {
            guard let opener = parseDetailsOpenTag(from: nodes[index]) else {
                result.append(nodes[index])
                index += 1
                continue
            }

            guard let closeIndex = findMatchingDetailsClose(in: nodes, startAt: index + 1) else {
                // Malformed HTML details block, keep original nodes untouched.
                result.append(nodes[index])
                index += 1
                continue
            }

            let innerNodes = Array(nodes[(index + 1)..<closeIndex])
            let extracted = extractSummaryAndBody(from: innerNodes)

            let detailsNode = DetailsNode(
                range: opener.range,
                isOpen: opener.isOpen,
                summary: extracted.summary,
                children: extracted.body
            )
            result.append(detailsNode)
            index = closeIndex + 1
        }

        return result
    }

    private func findMatchingDetailsClose(in nodes: [MarkdownNode], startAt start: Int) -> Int? {
        var depth = 1
        var index = start

        while index < nodes.count {
            if parseDetailsOpenTag(from: nodes[index]) != nil {
                depth += 1
            } else if isDetailsCloseTag(nodes[index]) {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }

        return nil
    }

    private func extractSummaryAndBody(from nodes: [MarkdownNode]) -> (summary: SummaryNode?, body: [MarkdownNode]) {
        guard let first = nodes.first else {
            return (nil, [])
        }

        if let summaryText = inlineSummaryText(from: first) {
            let summary = SummaryNode(
                range: first.range,
                children: summaryChildren(from: summaryText)
            )
            let bodyNodes = Array(nodes.dropFirst())
            return (summary, processBodySiblings(bodyNodes))
        }

        if isSummaryOpenTag(first), let closeIndex = findSummaryClose(in: nodes, startAt: 1) {
            let rawSummaryNodes = Array(nodes[1..<closeIndex])
            let bodyNodes = Array(nodes[(closeIndex + 1)...])

            let summary = SummaryNode(
                range: first.range,
                children: normalizedSummaryChildren(from: rawSummaryNodes)
            )
            return (summary, processBodySiblings(bodyNodes))
        }

        return (nil, processBodySiblings(nodes))
    }

    /// Apply expand + merge to a slice (e.g. the body of a newly-discovered
    /// `<details>` block) so nested `<details>` markup is also recognized.
    private func processBodySiblings(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        mergeDetails(in: expandDetailsHTMLTagNodes(in: nodes))
    }

    private func findSummaryClose(in nodes: [MarkdownNode], startAt start: Int) -> Int? {
        var index = start
        while index < nodes.count {
            if isSummaryCloseTag(nodes[index]) {
                return index
            }
            index += 1
        }
        return nil
    }

    private func normalizedSummaryChildren(from nodes: [MarkdownNode]) -> [MarkdownNode] {
        if nodes.count == 1, let paragraph = nodes[0] as? ParagraphNode {
            return processBodySiblings(paragraph.children)
        }
        return processBodySiblings(nodes)
    }

    private func summaryChildren(from text: String) -> [MarkdownNode] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [TextNode(range: nil, text: trimmed)]
    }

    private func parseDetailsOpenTag(from node: MarkdownNode) -> (isOpen: Bool, range: SourceRange?)? {
        guard let text = rawHTMLTagText(from: node), isMatch(Self.detailsOpenRegex, text: text) else {
            return nil
        }

        let isOpen = text.range(
            of: #"\bopen\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return (isOpen, node.range)
    }

    private func isDetailsCloseTag(_ node: MarkdownNode) -> Bool {
        guard let text = rawHTMLTagText(from: node) else { return false }
        return isMatch(Self.detailsCloseRegex, text: text)
    }

    private func isSummaryOpenTag(_ node: MarkdownNode) -> Bool {
        guard let text = rawHTMLTagText(from: node) else { return false }
        return isMatch(Self.summaryOpenRegex, text: text)
    }

    private func isSummaryCloseTag(_ node: MarkdownNode) -> Bool {
        guard let text = rawHTMLTagText(from: node) else { return false }
        return isMatch(Self.summaryCloseRegex, text: text)
    }

    private func inlineSummaryText(from node: MarkdownNode) -> String? {
        guard let text = rawHTMLTagText(from: node) else { return nil }
        guard let match = firstMatch(Self.summaryInlineRegex, text: text) else { return nil }
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func rawHTMLTagText(from node: MarkdownNode) -> String? {
        if let text = node as? TextNode {
            return text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let paragraph = node as? ParagraphNode {
            var fragments: [String] = []
            for child in paragraph.children {
                guard let text = child as? TextNode else { return nil }
                fragments.append(text.text)
            }
            return fragments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func expandDetailsHTMLTagNodes(in nodes: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []

        for node in nodes {
            guard let textNode = node as? TextNode else {
                result.append(node)
                continue
            }

            let raw = textNode.text
            guard raw.contains(where: \.isNewline), Self.looksLikeDetailsMarkup(raw) else {
                result.append(node)
                continue
            }

            let lines = raw
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if lines.isEmpty {
                continue
            }

            if lines.count == 1 {
                result.append(TextNode(range: textNode.range, text: lines[0]))
                continue
            }

            for line in lines {
                result.append(TextNode(range: textNode.range, text: line))
            }
        }

        return result
    }

    /// Shared marker check for multiline HTML expansion and whole-source preflight.
    /// The markers are ASCII HTML tag names, so scanning the UTF-8 view avoids
    /// allocating a lowercased copy of the full Markdown input.
    static func looksLikeDetailsMarkup(_ text: String) -> Bool {
        let bytes = text.utf8
        return Self.containsASCIICaseInsensitive(bytes, needle: Self.detailsOpenNeedle)
            || Self.containsASCIICaseInsensitive(bytes, needle: Self.detailsCloseNeedle)
            || Self.containsASCIICaseInsensitive(bytes, needle: Self.summaryOpenNeedle)
            || Self.containsASCIICaseInsensitive(bytes, needle: Self.summaryCloseNeedle)
    }

    private static let detailsOpenNeedle: [UInt8] = Array("<details".utf8)
    private static let detailsCloseNeedle: [UInt8] = Array("</details>".utf8)
    private static let summaryOpenNeedle: [UInt8] = Array("<summary".utf8)
    private static let summaryCloseNeedle: [UInt8] = Array("</summary>".utf8)

    /// Naive ASCII case-insensitive substring search over raw UTF-8 bytes.
    /// `needle` must already be lowercase ASCII. Non-ASCII bytes in `haystack`
    /// (high bit set) never fold to an ASCII letter, so they simply fail to
    /// match — safe for arbitrary UTF-8 input, including non-ASCII text.
    private static func containsASCIICaseInsensitive(_ haystack: String.UTF8View, needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return false }
        let firstNeedleByte = needle[0]
        var start = haystack.startIndex

        while start < haystack.endIndex {
            if Self.asciiLowercased(haystack[start]) == firstNeedleByte {
                var sourceIndex = haystack.index(after: start)
                var needleIndex = 1
                while needleIndex < needle.count {
                    guard sourceIndex < haystack.endIndex else { return false }
                    guard Self.asciiLowercased(haystack[sourceIndex]) == needle[needleIndex] else {
                        break
                    }
                    sourceIndex = haystack.index(after: sourceIndex)
                    needleIndex += 1
                }
                if needleIndex == needle.count { return true }
            }
            start = haystack.index(after: start)
        }
        return false
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        (byte >= 65 && byte <= 90) ? byte + 32 : byte
    }

    private func isMatch(_ regex: NSRegularExpression, text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return false
        }
        return match.range.location == 0 && match.range.length == range.length
    }

    private func firstMatch(_ regex: NSRegularExpression, text: String) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        guard match.range.location == 0, match.range.length == range.length else {
            return nil
        }
        return match
    }

    // swiftlint:disable force_try — patterns are compile-time string literals; failure is a programmer error.
    private static let detailsOpenRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^<details(?:\s+[^>]*)?>$"#) else {
            fatalError("Invalid regex pattern for detailsOpenRegex")
        }
        return regex
    }()

    private static let detailsCloseRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^</details>$"#) else {
            fatalError("Invalid regex pattern for detailsCloseRegex")
        }
        return regex
    }()

    private static let summaryOpenRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^<summary(?:\s+[^>]*)?>$"#) else {
            fatalError("Invalid regex pattern for summaryOpenRegex")
        }
        return regex
    }()

    private static let summaryCloseRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^</summary>$"#) else {
            fatalError("Invalid regex pattern for summaryCloseRegex")
        }
        return regex
    }()

    private static let summaryInlineRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)^<summary(?:\s+[^>]*)?>(.*?)</summary>$"#) else {
            fatalError("Invalid regex pattern for summaryInlineRegex")
        }
        return regex
    }()
    // swiftlint:enable force_try
}
