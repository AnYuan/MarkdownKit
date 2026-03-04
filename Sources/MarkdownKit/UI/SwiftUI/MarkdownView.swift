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
                    engine.toggleDetails(at: index, currentlyOpen: details.isOpen, width: geometry.size.width)
                },
                onLinkTap: linkTapHandler,
                onCheckboxToggle: checkboxToggleHandler
            )
            .onChange(of: text) { _, newText in
                engine.render(markdown: newText, plugins: plugins, theme: theme, width: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                engine.render(markdown: text, plugins: plugins, theme: theme, width: newWidth)
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
    
    func render(markdown: String, plugins: [ASTPlugin], theme: Theme, width: CGFloat) {
        guard width > 50 else { return }
        
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
    
    func toggleDetails(at index: Int, currentlyOpen: Bool, width: CGFloat) {
        guard let ast = lastAST, 
              ast.children.indices.contains(index),
              let details = ast.children[index] as? DetailsNode,
              let theme = lastTheme else { return }
        
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
            let result = await solver.solve(node: toggledDocument, constrainedToWidth: width)
            
            if Task.isCancelled { return }
            
            self.lastAST = toggledDocument
            self.layouts = result.children
        }
    }
}
#endif
