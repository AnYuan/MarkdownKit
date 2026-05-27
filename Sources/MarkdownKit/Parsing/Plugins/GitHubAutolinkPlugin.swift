import Foundation
import Markdown

/// A parsing middleware plugin that detects custom textual patterns
/// and wraps them in actionable `LinkNode` elements pointing back to a host application.
public struct GitHubAutolinkPlugin: ASTPlugin {

    public weak var delegate: MarkdownContextDelegate?

    // Regular expressions for GitHub-style tokens (compile-time string literals — patterns are guaranteed valid)
    private static let mentionPattern = "(?<![a-zA-Z0-9])@([a-zA-Z0-9-]+)"
    private static let referencePattern = "(?<![a-zA-Z0-9])([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)?#([0-9]+)"
    private static let commitPattern = "(?<![a-zA-Z0-9])[0-9a-f]{7,40}(?![a-zA-Z0-9])"

    private let mentionRegex: NSRegularExpression
    private let referenceRegex: NSRegularExpression
    private let commitRegex: NSRegularExpression

    public init(delegate: MarkdownContextDelegate? = nil) {
        self.delegate = delegate

        guard let mention = try? NSRegularExpression(pattern: Self.mentionPattern, options: []),
              let reference = try? NSRegularExpression(pattern: Self.referencePattern, options: []),
              let commit = try? NSRegularExpression(pattern: Self.commitPattern, options: []) else {
            fatalError("GitHubAutolinkPlugin: invalid regex pattern — this is a programmer error")
        }
        self.mentionRegex = mention
        self.referenceRegex = reference
        self.commitRegex = commit
    }

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        // The 23-case per-container `switch` previously here is replaced by
        // `AST.transform`. The visitor's only responsibility is the per-node
        // decision: scan TextNodes for autolink patterns, and block recursion
        // into nodes whose contents must not be re-linked (LinkNode, code, etc.).
        AST.transform(nodes) { node in
            switch node {
            case let text as TextNode:
                let rewritten = processTextNode(text)
                if rewritten.count == 1, rewritten[0].id == text.id {
                    return .unchanged
                }
                return .replaceMany(rewritten)

            // Never autolink inside an existing LinkNode (breaks hrefs) or
            // inside raw/formatted-data leaves.
            case is LinkNode,
                 is CodeBlockNode,
                 is InlineCodeNode,
                 is DiagramNode,
                 is MathNode,
                 is ImageNode:
                return .skipChildren(node)

            default:
                return .unchanged
            }
        }
    }

    /// Scans a text string for mentions, SHAs, and issues, returning an array of split nodes.
    /// Returns the input node verbatim (identity preserved) when no token matches.
    private func processTextNode(_ textNode: TextNode) -> [MarkdownNode] {
        let string = textNode.text

        // Fast path: skip regex work entirely when no marker char is present.
        // Mentions need `@`, references need `#`, commits need a hex run.
        var hasMentionOrReferenceMarker = false
        var hasHexRun = false
        for ch in string {
            if ch == "@" || ch == "#" {
                hasMentionOrReferenceMarker = true
            }
            if ch.isHexDigit {
                hasHexRun = true
            }
            if hasMentionOrReferenceMarker && hasHexRun { break }
        }
        if !hasMentionOrReferenceMarker && !hasHexRun {
            return [textNode]
        }

        let nsString = string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Find all matches across all types
        var matches: [(range: NSRange, type: MatchType, matchedString: String, extracted: String)] = []

        if hasMentionOrReferenceMarker {
            mentionRegex.enumerateMatches(in: string, options: [], range: fullRange) { result, _, _ in
                if let result = result {
                    let matched = nsString.substring(with: result.range)
                    let username = nsString.substring(with: result.range(at: 1))
                    matches.append((result.range, .mention, matched, username))
                }
            }

            referenceRegex.enumerateMatches(in: string, options: [], range: fullRange) { result, _, _ in
                if let result = result {
                    let matched = nsString.substring(with: result.range)
                    matches.append((result.range, .reference, matched, matched))
                }
            }
        }

        if hasHexRun {
            commitRegex.enumerateMatches(in: string, options: [], range: fullRange) { result, _, _ in
                if let result = result {
                    let matched = nsString.substring(with: result.range)
                    matches.append((result.range, .commit, matched, matched))
                }
            }
        }

        // Sort matches sequentially
        matches.sort { $0.range.location < $1.range.location }

        // Remove overlaps (longest match first strategy or simple first-wins)
        var filteredMatches: [(range: NSRange, type: MatchType, matchedString: String, extracted: String)] = []
        for match in matches {
            let overlaps = filteredMatches.contains {
                NSIntersectionRange($0.range, match.range).length > 0
            }
            if !overlaps {
                filteredMatches.append(match)
            }
        }

        guard !filteredMatches.isEmpty else { return [textNode] }

        var resultingNodes = [MarkdownNode]()
        var currentIndex = 0

        for match in filteredMatches {
            // Append preceding text if any
            if match.range.location > currentIndex {
                let textRange = NSRange(location: currentIndex, length: match.range.location - currentIndex)
                resultingNodes.append(TextNode(range: textNode.range, text: nsString.substring(with: textRange)))
            }

            // Append the actual autolink
            let urlString: String
            switch match.type {
            case .mention:
                urlString = delegate?.resolveMention(username: match.extracted)?.absoluteString ?? "x-mention://\(match.extracted)"
            case .reference:
                urlString = delegate?.resolveReference(reference: match.extracted)?.absoluteString ?? "x-reference://\(match.extracted)"
            case .commit:
                urlString = delegate?.resolveCommit(sha: match.extracted)?.absoluteString ?? "x-commit://\(match.extracted)"
            }

            let linkNode = LinkNode(
                range: textNode.range,
                destination: urlString,
                title: match.matchedString,
                children: [
                    // Commits render as inline code inside the link; other autolinks are plain text.
                    match.type == .commit
                        ? InlineCodeNode(range: nil, code: match.matchedString)
                        : TextNode(range: nil, text: match.matchedString)
                ]
            )
            resultingNodes.append(linkNode)

            currentIndex = NSMaxRange(match.range)
        }

        // Append trailing text if any
        if currentIndex < nsString.length {
            let trailingRange = NSRange(location: currentIndex, length: nsString.length - currentIndex)
            resultingNodes.append(TextNode(range: textNode.range, text: nsString.substring(with: trailingRange)))
        }

        return resultingNodes
    }

    private enum MatchType {
        case mention
        case reference
        case commit
    }
}
