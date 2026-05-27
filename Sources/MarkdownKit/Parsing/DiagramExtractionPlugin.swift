import Foundation

/// An ASTPlugin that upgrades diagram-oriented fenced code blocks to `DiagramNode`.
///
/// Supported languages: mermaid, geojson, topojson, stl.
public struct DiagramExtractionPlugin: ASTPlugin {
    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        AST.transform(nodes) { node in
            guard let code = node as? CodeBlockNode,
                  let language = diagramLanguage(from: code.language) else {
                return .unchanged
            }
            return .replace(DiagramNode(range: code.range, language: language, source: code.code))
        }
    }

    private func diagramLanguage(from raw: String?) -> DiagramLanguage? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DiagramLanguage(rawValue: normalized)
    }
}
