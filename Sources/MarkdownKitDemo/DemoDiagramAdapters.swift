#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import Foundation
import MarkdownKit

enum DemoDiagramAdapters {
    static func makeRegistry() -> DiagramAdapterRegistry {
        var registry = DiagramAdapterRegistry()
        registry.register(DemoMermaidAdapter(), for: .mermaid)
        registry.register(DemoGeoJSONAdapter(kind: "GeoJSON"), for: .geojson)
        registry.register(DemoGeoJSONAdapter(kind: "TopoJSON"), for: .topojson)
        registry.register(DemoSTLAdapter(), for: .stl)
        return registry
    }
}

private struct DemoGeoJSONAdapter: DiagramRenderingAdapter {
    let kind: String

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        guard language == .geojson || language == .topojson else { return nil }

        var lines: [String] = []
        if let data = source.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let type = (json["type"] as? String) ?? "Unknown"
            lines.append("Type: \(type)")

            if let features = json["features"] as? [Any] {
                lines.append("Features: \(features.count)")
            }
            if let objects = json["objects"] as? [String: Any] {
                lines.append("Objects: \(objects.count)")
            }
        } else {
            lines.append("Invalid JSON")
        }

        return makeSummaryCard(title: kind, lines: lines)
    }
}

private struct DemoSTLAdapter: DiagramRenderingAdapter {
    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        guard language == .stl else { return nil }

        let facetCount = source.components(separatedBy: "facet normal").count - 1
        let vertexCount = source.components(separatedBy: "vertex ").count - 1
        let lines = [
            "Facets: \(max(0, facetCount))",
            "Vertices: \(max(0, vertexCount))"
        ]
        return makeSummaryCard(title: "STL Mesh", lines: lines)
    }
}

private struct DemoMermaidAdapter: DiagramRenderingAdapter {
    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        guard language == .mermaid else { return nil }

        let summary = summarizeMermaid(source)
        var lines = [
            "Direction: \(summary.direction)",
            "Nodes: \(summary.nodes.count)",
            "Edges: \(summary.edges.count)"
        ]

        if !summary.edges.isEmpty {
            lines.append("Sample edges:")
            lines.append(contentsOf: summary.edges.prefix(4).map { "\($0.from) -> \($0.to)" })
        }

        if summary.nodes.isEmpty && summary.edges.isEmpty {
            lines.append("No parsable nodes/edges found.")
        }

        return makeSummaryCard(title: "Mermaid Graph", lines: lines)
    }
}

private struct MermaidSummary {
    struct Edge {
        let from: String
        let to: String
    }

    let direction: String
    let nodes: Set<String>
    let edges: [Edge]
}

private func summarizeMermaid(_ source: String) -> MermaidSummary {
    let rawLines = source
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.hasPrefix("%%") }

    var direction = "Unknown"
    if let graphLine = rawLines.first(where: { $0.lowercased().hasPrefix("graph ") }) {
        let parts = graphLine.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2 {
            direction = String(parts[1]).uppercased()
        }
    }

    var nodes: Set<String> = []
    var edges: [MermaidSummary.Edge] = []

    for line in rawLines {
        let sanitized = line.replacingOccurrences(
            of: #"\|[^|]*\|"#,
            with: " ",
            options: .regularExpression
        )

        guard let arrow = firstArrowToken(in: sanitized) else { continue }
        let parts = sanitized.components(separatedBy: arrow)
        guard parts.count >= 2,
              let left = nodeTokenAtEnd(parts[0]),
              let right = nodeTokenAtStart(parts[1]) else {
            continue
        }

        nodes.insert(left)
        nodes.insert(right)
        edges.append(.init(from: left, to: right))
    }

    return MermaidSummary(direction: direction, nodes: nodes, edges: edges)
}

private func firstArrowToken(in line: String) -> String? {
    let arrows = ["-.->", "==>", "-->"]
    return arrows.first(where: { line.contains($0) })
}

private func nodeTokenAtEnd(_ fragment: String) -> String? {
    let cleaned = stripMermaidDecorations(fragment)
    let tokens = cleaned.split(whereSeparator: \.isWhitespace)
    return tokens.last.map(String.init)
}

private func nodeTokenAtStart(_ fragment: String) -> String? {
    let cleaned = stripMermaidDecorations(fragment)
    let tokens = cleaned.split(whereSeparator: \.isWhitespace)
    return tokens.first.map(String.init)
}

private func stripMermaidDecorations(_ fragment: String) -> String {
    fragment
        .replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\([^\)]*\)"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\{[^\}]*\}"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"[;,]"#, with: " ", options: .regularExpression)
}

private func makeSummaryCard(title: String, lines: [String]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.labelColor
    ]
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    result.append(NSAttributedString(string: "\(title)\n", attributes: titleAttrs))
    for line in lines {
        result.append(NSAttributedString(string: "\(line)\n", attributes: bodyAttrs))
    }
    return result
}
#endif
