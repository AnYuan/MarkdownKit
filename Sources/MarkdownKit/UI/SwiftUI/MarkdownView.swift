#if canImport(SwiftUI)
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// A cross-platform SwiftUI wrapper for `MarkdownCollectionView`.
@available(iOS 14.0, macOS 11.0, *)
public struct MarkdownView: View {
    private let text: String
    private let theme: Theme
    private let plugins: [ASTPlugin]
    private var linkTapHandler: ((URL) -> Void)?
    private var checkboxToggleHandler: ((CheckboxInteractionData) -> Void)?

    @StateObject private var engine = MarkdownEngine()

    /// Initializes a high-performance native Markdown view.
    /// - Parameters:
    ///   - text: The Raw Markdown string to render.
    ///   - theme: The visual appearance theme for text and blocks. Defaults to `.default`.
    ///   - plugins: A list of AST plugins to mutate the syntax tree before measuring layout.
    public init(
        text: String,
        theme: Theme = .default,
        plugins: [ASTPlugin] = [DetailsExtractionPlugin(), DiagramExtractionPlugin(), MathExtractionPlugin()]
    ) {
        self.text = text
        self.theme = theme
        self.plugins = plugins
    }

    public var body: some View {
        GeometryReader { geometry in
            MarkdownViewRepresentable(
                layouts: engine.layouts,
                onToggleDetails: { index, details in
                    engine.toggleDetails(
                        at: index,
                        currentlyOpen: details.isOpen,
                        width: engine.preferredWidth(fallback: geometry.size.width)
                    )
                },
                onEffectiveContentWidthChange: { newWidth in
                    engine.updateEffectiveContentWidth(
                        newWidth,
                        markdown: text,
                        plugins: plugins,
                        theme: theme
                    )
                },
                onLinkTap: linkTapHandler,
                onCheckboxToggle: checkboxToggleHandler,
                theme: theme
            )
            .onChange(of: text) { _, newText in
                engine.renderForCurrentPlatform(
                    markdown: newText,
                    plugins: plugins,
                    theme: theme,
                    fallbackWidth: geometry.size.width
                )
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                engine.renderOnGeometryChange(
                    markdown: text,
                    plugins: plugins,
                    theme: theme,
                    newWidth: newWidth
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

    func preferredWidth(fallback: CGFloat) -> CGFloat {
        currentWidth > 50 ? currentWidth : fallback
    }
    
    func render(markdown: String, plugins: [ASTPlugin], theme: Theme, width: CGFloat) {
        guard width > 50 else { return }

        currentWidth = width
        renderTask?.cancel()
        renderTask = Task {
            let parser = MarkdownParser(plugins: plugins)
            let solver = LayoutSolver(theme: theme)
            let ast = parser.parse(markdown)
            
            // If the task was cancelled while parsing, bail out early
            if Task.isCancelled { return }
            
            let result = await solver.solve(node: ast, constrainedToWidth: width)
            
            if Task.isCancelled { return }
            
            self.lastAST = ast
            self.lastTheme = theme
            self.layouts = result.children
        }
    }

    func renderForCurrentPlatform(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        fallbackWidth: CGFloat
    ) {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        guard currentWidth > 50 else { return }
        render(markdown: markdown, plugins: plugins, theme: theme, width: currentWidth)
        #else
        render(markdown: markdown, plugins: plugins, theme: theme, width: preferredWidth(fallback: fallbackWidth))
        #endif
    }

    func renderOnGeometryChange(
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme,
        newWidth: CGFloat
    ) {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        // AppKit re-reports the true scroll-content width from the NSView bridge.
        // Rendering here causes a transient first-pass mismatch on startup and resize.
        return
        #else
        render(markdown: markdown, plugins: plugins, theme: theme, width: preferredWidth(fallback: newWidth))
        #endif
    }

    func updateEffectiveContentWidth(
        _ width: CGFloat,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme
    ) {
        guard width > 50 else { return }
        guard abs(width - currentWidth) > 0.5 else { return }

        render(markdown: markdown, plugins: plugins, theme: theme, width: width)
    }
    
    func toggleDetails(at index: Int, currentlyOpen: Bool, width: CGFloat) {
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
        
        renderTask?.cancel()
        renderTask = Task {
            let solver = LayoutSolver(theme: theme)
            let result = await solver.solve(node: toggledDocument, constrainedToWidth: resolvedWidth)
            
            if Task.isCancelled { return }
            
            self.lastAST = toggledDocument
            self.layouts = result.children
        }
    }
}
#endif
