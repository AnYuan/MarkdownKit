import Foundation

/// An ASTPlugin that upgrades diagram-oriented fenced code blocks to `DiagramNode`.
///
/// Supported languages: mermaid, geojson, topojson, stl.
public struct DiagramExtractionPlugin: ASTPlugin {
    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        AST.transform(nodes) { node in
            guard let code = node as? CodeBlockNode,
                  let language = Self.diagramLanguage(from: code.language) else {
                return .unchanged
            }
            return .replace(DiagramNode(range: code.range, language: language, source: code.code))
        }
    }

    /// The single source of truth mapping a fenced code block's raw language string
    /// to a supported `DiagramLanguage`. Shared by `visit(_:)` and by
    /// `BuiltInPluginSourceHints`, which reuses it against fence-language candidates
    /// scanned from the raw source as a conservative preflight check.
    static func diagramLanguage(from raw: String?) -> DiagramLanguage? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DiagramLanguage(rawValue: normalized)
    }
}
