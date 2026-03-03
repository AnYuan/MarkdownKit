import Foundation
import CoreGraphics

#if canImport(SwiftUI)
@_exported import SwiftUI
#endif

// Re-export splash so users can customize formatting if they want
@_exported import Splash

/// Convenience entry points for constructing parser/layout pipelines with sensible defaults.
public enum MarkdownKitEngine {

    /// Returns the default plugin pipeline used by MarkdownKit.
    ///
    /// Default order:
    /// 1. Details extraction
    /// 2. Diagram extraction
    /// 3. Math extraction
    /// 4. Optional GitHub-style autolinks
    public static func defaultPlugins(
        contextDelegate: MarkdownContextDelegate? = nil,
        includeGitHubAutolinks: Bool = false
    ) -> [ASTPlugin] {
        var plugins: [ASTPlugin] = [
            DetailsExtractionPlugin(),
            DiagramExtractionPlugin(),
            MathExtractionPlugin()
        ]

        if includeGitHubAutolinks {
            plugins.append(GitHubAutolinkPlugin(delegate: contextDelegate))
        }

        return plugins
    }

    /// Builds a parser using either a supplied plugin list or the default plugin pipeline.
    public static func makeParser(
        plugins: [ASTPlugin]? = nil,
        contextDelegate: MarkdownContextDelegate? = nil,
        includeGitHubAutolinks: Bool = false
    ) -> MarkdownParser {
        let resolvedPlugins = plugins ?? defaultPlugins(
            contextDelegate: contextDelegate,
            includeGitHubAutolinks: includeGitHubAutolinks
        )
        return MarkdownParser(plugins: resolvedPlugins)
    }

    /// Builds a layout solver with configurable theme/cache/diagram registry.
    public static func makeLayoutSolver(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry()
    ) -> LayoutSolver {
        LayoutSolver(
            theme: theme,
            cache: cache,
            diagramRegistry: diagramRegistry
        )
    }

    /// Parse markdown and solve layout in one call.
    ///
    /// - Parameters:
    ///   - markdown: Raw markdown content
    ///   - constrainedToWidth: Container width for wrapping and sizing
    ///   - parser: Optional parser instance. If omitted, a default parser is used.
    ///   - solver: Optional solver instance. If omitted, a default solver is used.
    public static func layout(
        markdown: String,
        constrainedToWidth width: CGFloat,
        parser: MarkdownParser? = nil,
        solver: LayoutSolver? = nil
    ) async -> LayoutResult {
        let resolvedParser = parser ?? makeParser()
        let resolvedSolver = solver ?? makeLayoutSolver()
        let document = resolvedParser.parse(markdown)
        return await resolvedSolver.solve(node: document, constrainedToWidth: width)
    }
}
