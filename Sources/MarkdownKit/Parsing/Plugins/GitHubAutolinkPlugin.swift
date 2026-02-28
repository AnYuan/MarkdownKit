import Foundation
import Markdown

/// A parsing middleware plugin that detects custom textual patterns
/// and wraps them in actionable `LinkNode` elements pointing back to a host application.
public struct GitHubAutolinkPlugin: ASTPlugin {
    
    public weak var delegate: MarkdownContextDelegate?
    
    // Regular expressions for GitHub-style tokens
    private let mentionRegex: NSRegularExpression
    private let referenceRegex: NSRegularExpression
    private let commitRegex: NSRegularExpression
    
    public init(delegate: MarkdownContextDelegate? = nil) {
        self.delegate = delegate
        
        // Match @username (alphanumeric with hyphens, not at the start of a word boundary necessarily if preceded by space)
        self.mentionRegex = try! NSRegularExpression(pattern: "(?<![a-zA-Z0-9])@([a-zA-Z0-9-]+)", options: [])
        
        // Match #1234 or owner/repo#1234
        self.referenceRegex = try! NSRegularExpression(pattern: "(?<![a-zA-Z0-9])([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)?#([0-9]+)", options: [])
        
        // Match 7-40 hex chars for SHAs
        self.commitRegex = try! NSRegularExpression(pattern: "(?<![a-zA-Z0-9])[0-9a-f]{7,40}(?![a-zA-Z0-9])", options: [])
    }
    
    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        var newNodes = [MarkdownNode]()
        
        for node in nodes {
            switch node {
            case let text as TextNode:
                // Try splitting the text node based on regex matches
                newNodes.append(contentsOf: processTextNode(text))
                
            case let doc as DocumentNode:
                newNodes.append(DocumentNode(range: doc.range, children: visit(doc.children)))
            case let bq as BlockQuoteNode:
                newNodes.append(BlockQuoteNode(range: bq.range, children: visit(bq.children)))
            case let list as ListNode:
                newNodes.append(ListNode(range: list.range, isOrdered: list.isOrdered, children: visit(list.children)))
            case let item as ListItemNode:
                newNodes.append(ListItemNode(range: item.range, checkbox: item.checkbox, children: visit(item.children)))
            case let para as ParagraphNode:
                newNodes.append(ParagraphNode(range: para.range, children: visit(para.children)))
            case let header as HeaderNode:
                newNodes.append(HeaderNode(range: header.range, level: header.level, children: visit(header.children)))
            case let table as TableNode:
                newNodes.append(TableNode(range: table.range, columnAlignments: table.columnAlignments, children: visit(table.children)))
            case let head as TableHeadNode:
                newNodes.append(TableHeadNode(range: head.range, children: visit(head.children)))
            case let body as TableBodyNode:
                newNodes.append(TableBodyNode(range: body.range, children: visit(body.children)))
            case let row as TableRowNode:
                newNodes.append(TableRowNode(range: row.range, children: visit(row.children)))
            case let cell as TableCellNode:
                newNodes.append(TableCellNode(range: cell.range, children: visit(cell.children)))
            case let strong as StrongNode:
                newNodes.append(StrongNode(range: strong.range, children: visit(strong.children)))
            case let emp as EmphasisNode:
                newNodes.append(EmphasisNode(range: emp.range, children: visit(emp.children)))
            case let strike as StrikethroughNode:
                newNodes.append(StrikethroughNode(range: strike.range, children: visit(strike.children)))
            case let details as DetailsNode:
                newNodes.append(DetailsNode(range: details.range, isOpen: details.isOpen, summary: details.summary, children: visit(details.children)))
            case let summary as SummaryNode:
                newNodes.append(SummaryNode(range: summary.range, children: visit(summary.children)))
            case let link as LinkNode:
                // Do NOT recursively autolink inside an existing link or it breaks hrefs
                newNodes.append(link)
            case is CodeBlockNode, is InlineCodeNode, is DiagramNode, is MathNode, is ImageNode:
                // Raw data blocks or already formatted elements shouldn't have inner text randomly linked
                newNodes.append(node)
            default:
                newNodes.append(node)
            }
        }
        
        return newNodes
    }
    
    /// Scans a text string for mentions, SHAs, and issues, returning an array of split nodes.
    private func processTextNode(_ textNode: TextNode) -> [MarkdownNode] {
        let string = textNode.text
        let nsString = string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        
        // Find all matches across all types
        var matches: [(range: NSRange, type: MatchType, matchedString: String, extracted: String)] = []
        
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
        
        commitRegex.enumerateMatches(in: string, options: [], range: fullRange) { result, _, _ in
            if let result = result {
                let matched = nsString.substring(with: result.range)
                matches.append((result.range, .commit, matched, matched))
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
                    // We must apply inline code styling manually via tokenizer, or just let it text.
                    // Let's use standard text node inside the link, or inline code for commits.
                    match.type == .commit ? 
                        InlineCodeNode(range: nil, code: match.matchedString) : 
                        TextNode(range: nil, text: match.matchedString)
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
