#if canImport(SwiftUI)
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// Controls how MarkdownKit renders text-bearing blocks.
public enum MarkdownTextInteractionMode: Sendable {
    /// Preserves the existing high-performance async rasterized text path.
    case asyncReadOnly
    /// Uses a native text view so users can select text.
    case selectableNative
}

/// A cross-platform SwiftUI wrapper for `MarkdownCollectionView`.
@available(iOS 14.0, macOS 11.0, *)
public struct MarkdownView: View {
    private let text: String
    private let theme: Theme
    private let plugins: [ASTPlugin]
    private let diagramRegistry: DiagramAdapterRegistry
    private let imageLoadingPolicy: ImageLoadingPolicy
    private var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly
    private var linkTapHandler: ((URL) -> Void)?
    private var checkboxToggleHandler: ((CheckboxInteractionData) -> Void)?

    @StateObject private var engine = MarkdownEngine()

    /// Initializes a high-performance native Markdown view.
    /// - Parameters:
    ///   - text: The Raw Markdown string to render.
    ///   - theme: The visual appearance theme for text and blocks. Defaults to `.default`.
    ///   - plugins: A list of AST plugins to mutate the syntax tree before measuring layout.
    ///   - diagramRegistry: Host-provided diagram renderers used for diagram code fences.
    ///   - imageLoadingPolicy: Host-controlled rules for Markdown image sources.
    public init(
        text: String,
        theme: Theme = .default,
        plugins: [ASTPlugin] = [DetailsExtractionPlugin(), DiagramExtractionPlugin(), MathExtractionPlugin()],
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) {
        self.text = text
        self.theme = theme
        self.plugins = plugins
        self.diagramRegistry = diagramRegistry
        self.imageLoadingPolicy = imageLoadingPolicy
    }

    public var body: some View {
        GeometryReader { geometry in
            MarkdownViewRepresentable(
                layouts: engine.layouts,
                onToggleDetails: { index, details in
                    engine.toggleDetails(
                        at: index,
                        currentlyOpen: details.isOpen,
                        width: engine.preferredWidth(fallback: geometry.size.width),
                        diagramRegistry: diagramRegistry,
                        imageLoadingPolicy: imageLoadingPolicy
                    )
                },
                onEffectiveContentWidthChange: { newWidth in
                    engine.updateEffectiveContentWidth(
                        newWidth,
                        markdown: text,
                        plugins: plugins,
                        theme: theme,
                        diagramRegistry: diagramRegistry,
                        imageLoadingPolicy: imageLoadingPolicy
                    )
                },
                onLinkTap: linkTapHandler,
                onCheckboxToggle: checkboxToggleHandler,
                theme: theme,
                textInteractionMode: textInteractionMode,
                imageLoadingPolicy: imageLoadingPolicy
            )
            .task {
                // First paint is immediate — debouncing here would add latency
                // before any text appears.
                engine.renderForCurrentPlatform(
                    markdown: text,
                    plugins: plugins,
                    theme: theme,
                    fallbackWidth: geometry.size.width,
                    diagramRegistry: diagramRegistry,
                    imageLoadingPolicy: imageLoadingPolicy
                )
            }
            // Single `.onChange` over a combined input so a simultaneous
            // text+width change only triggers one render (the previous code
            // could race two cancellations).
            .onChange(of: RenderInput(text: text, width: geometry.size.width)) { _, newInput in
                engine.scheduleDebouncedTextRender(
                    markdown: newInput.text,
                    plugins: plugins,
                    theme: theme,
                    fallbackWidth: newInput.width,
                    diagramRegistry: diagramRegistry,
                    imageLoadingPolicy: imageLoadingPolicy
                )
            }
        }
    }

    /// Registers a callback when the user taps a link in the rendered markdown.
    /// If no callback is registered, links open in the default browser.
    public func onLinkTap(_ handler: @escaping (URL) -> Void) -> MarkdownView {
        var copy = self
        copy.linkTapHandler = handler
        return copy
    }

    /// Registers a callback when the user toggles a checkbox in the rendered markdown.
    public func onCheckboxToggle(_ handler: @escaping (CheckboxInteractionData) -> Void) -> MarkdownView {
        var copy = self
        copy.checkboxToggleHandler = handler
        return copy
    }

    /// Selects whether MarkdownKit should keep the async read-only renderer or
    /// switch to a native selectable text surface for text-bearing blocks.
    public func textInteractionMode(_ mode: MarkdownTextInteractionMode) -> MarkdownView {
        var copy = self
        copy.textInteractionMode = mode
        return copy
    }
}

/// Combined input for the single `.onChange` so simultaneous text + width
/// changes coalesce into one render task.
@available(iOS 14.0, macOS 11.0, *)
private struct RenderInput: Equatable {
    let text: String
    let width: CGFloat
}

// MARK: - Async Rendering Engine

@available(iOS 14.0, macOS 11.0, *)
@MainActor
private final class MarkdownEngine: ObservableObject {
    @Published var layouts: [LayoutResult] = []

    // Keep reference to the latest task to cancel on rapid typing/resizing
    private var renderTask: Task<Void, Never>?

    // Cache the previous successful AST and parser to enable fast sub-tree toggling (Details Node)
    private var lastAST: DocumentNode?
    private var lastTheme: Theme?
    private var currentWidth: CGFloat = 0

    /// Persistent layout cache shared across renders. Without this, streaming /
    /// per-keystroke re-renders create a fresh LayoutSolver (hence fresh cache)
    /// and identical un-changed blocks are re-laid out every time.
    private let layoutCache = LayoutCache()

    /// Cached LayoutSolver reused while theme / diagram registry / image policy
    /// stay unchanged. Recreating a solver when those *do* change is correct
    /// because the variant hash they feed into would also change — old cache
    /// entries simply don't match and sit until evicted.
    private var cachedSolver: LayoutSolver?
    private var cachedSolverKey: SolverKey?

    private struct SolverKey: Equatable {
        let theme: Theme
        let diagramFingerprint: Int
        let policyFingerprint: Int
    }

    private func solver(
        for theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) -> LayoutSolver {
        let key = SolverKey(
            theme: theme,
            diagramFingerprint: diagramRegistry.cacheFingerprint,
            policyFingerprint: imageLoadingPolicy.cacheFingerprint
        )
        if let solver = cachedSolver, cachedSolverKey == key {
            return solver
        }
        let solver = LayoutSolver(
            theme: theme,
            cache: layoutCache,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )
        cachedSolver = solver
        cachedSolverKey = key
        return solver
    }

    private struct RenderJob: @unchecked Sendable {
        let markdown: String
        let plugins: [ASTPlugin]
        let solver: LayoutSolver
        let width: CGFloat
        let theme: Theme
    }

    private struct RenderOutput: @unchecked Sendable {
        let ast: DocumentNode
        let theme: Theme
        let childLayouts: [LayoutResult]
    }

    func preferredWidth(fallback: CGFloat) -> CGFloat {
        currentWidth > 50 ? currentWidth : fallback
    }

    func render(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        width: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) {
        guard width > 50 else { return }

        currentWidth = width
        renderTask?.cancel()
        let solver = self.solver(
            for: theme,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )
        let job = RenderJob(
            markdown: markdown,
            plugins: plugins,
            solver: solver,
            width: width,
            theme: theme
        )

        renderTask = Task {
            let detached = Task.detached(priority: .userInitiated) {
                await Self.renderOffMain(job)
            }
            let output = await withTaskCancellationHandler {
                await detached.value
            } onCancel: {
                detached.cancel()
            }

            guard !Task.isCancelled, let output else { return }

            self.lastAST = output.ast
            self.lastTheme = output.theme
            self.layouts = output.childLayouts
        }
    }

    private nonisolated static func renderOffMain(_ job: RenderJob) async -> RenderOutput? {
        let parser = MarkdownParser(plugins: job.plugins)
        let ast = parser.parse(job.markdown)

        guard !Task.isCancelled else { return nil }

        let result = await job.solver.solve(node: ast, constrainedToWidth: job.width)

        guard !Task.isCancelled else { return nil }

        return RenderOutput(
            ast: ast,
            theme: job.theme,
            childLayouts: result.children
        )
    }

    func renderForCurrentPlatform(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        fallbackWidth: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        guard currentWidth > 50 else { return }
        render(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            width: currentWidth,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )
        #else
        render(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            width: preferredWidth(fallback: fallbackWidth),
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )
        #endif
    }

    /// Debounced wrapper for text/width changes. Sleeps for `debounceDelay`
    /// before kicking off the actual parse + layout work. Each new call
    /// supersedes any pending one, so a fast typist sees a single render
    /// after they pause instead of one per keystroke.
    func scheduleDebouncedTextRender(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        fallbackWidth: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard !Task.isCancelled, let self else { return }
            self.renderForCurrentPlatform(
                markdown: markdown,
                plugins: plugins,
                theme: theme,
                fallbackWidth: fallbackWidth,
                diagramRegistry: diagramRegistry,
                imageLoadingPolicy: imageLoadingPolicy
            )
        }
    }

    // `renderOnGeometryChange` lived here until Phase 4.6 collapsed the two
    // separate `.onChange` handlers (text + width) into one debounced
    // `scheduleDebouncedTextRender` call. The remaining `updateEffectiveContent-
    // Width` below still serves the macOS NSScrollView feedback path.

    func updateEffectiveContentWidth(
        _ width: CGFloat,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) {
        guard width > 50 else { return }
        guard abs(width - currentWidth) > 0.5 else { return }

        render(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            width: width,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )
    }
    
    func toggleDetails(
        at index: Int,
        currentlyOpen: Bool,
        width: CGFloat,
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) {
        guard let ast = lastAST,
              ast.children.indices.contains(index),
              let details = ast.children[index] as? DetailsNode,
              let theme = lastTheme else { return }

        let resolvedWidth = preferredWidth(fallback: width)

        var updatedChildren = ast.children
        updatedChildren[index] = DetailsNode(
            range: details.range,
            isOpen: !currentlyOpen,
            summary: details.summary,
            children: details.children
        )
        let toggledDocument = DocumentNode(range: ast.range, children: updatedChildren)

        // Reuse the persistent solver so unchanged sibling blocks (everything
        // except the toggled DetailsNode) come back from cache instead of being
        // re-measured.
        let solver = self.solver(
            for: theme,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )

        renderTask?.cancel()
        renderTask = Task {
            let result = await solver.solve(node: toggledDocument, constrainedToWidth: resolvedWidth)

            if Task.isCancelled { return }

            self.lastAST = toggledDocument
            self.layouts = result.children
        }
    }
}
#endif
