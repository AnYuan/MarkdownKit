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
    private let resourceLimits: MarkdownParser.ResourceLimits
    private var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly
    private var linkTapHandler: ((URL) -> Void)?
    private var checkboxToggleHandler: ((CheckboxInteractionData) -> Void)?

    @StateObject private var engine = MarkdownEngine()
    @Environment(\.colorScheme) private var colorScheme

    /// Initializes a high-performance native Markdown view.
    /// - Parameters:
    ///   - text: The Raw Markdown string to render.
    ///   - theme: The visual appearance theme for text and blocks. Defaults to `.default`.
    ///   - plugins: A list of AST plugins to mutate the syntax tree before measuring layout.
    ///   - diagramRegistry: Host-provided diagram renderers used for diagram code fences.
    ///   - imageLoadingPolicy: Host-controlled rules for Markdown image sources.
    ///   - resourceLimits: The per-parser resource policy bounding input size and native-AST
    ///     mapping recursion for every parse this view triggers. Defaults to
    ///     `MarkdownParser.ResourceLimits.default`.
    public init(
        text: String,
        theme: Theme = .default,
        plugins: [ASTPlugin] = [DetailsExtractionPlugin(), DiagramExtractionPlugin(), MathExtractionPlugin()],
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        imageLoadingPolicy: ImageLoadingPolicy = .default,
        resourceLimits: MarkdownParser.ResourceLimits = .default
    ) {
        self.text = text
        self.theme = theme
        self.plugins = plugins
        self.diagramRegistry = diagramRegistry
        self.imageLoadingPolicy = imageLoadingPolicy
        self.resourceLimits = resourceLimits
    }

    public var body: some View {
        GeometryReader { geometry in
            let appearance = MarkdownAppearance(colorScheme: colorScheme)
            let renderInput = MarkdownRenderInput(
                text: text,
                width: geometry.size.width,
                resourceLimits: resourceLimits,
                appearance: appearance,
                theme: theme,
                plugins: plugins,
                diagramRegistry: diagramRegistry,
                imageLoadingPolicy: imageLoadingPolicy
            )

            MarkdownViewRepresentable(
                layouts: engine.layouts,
                onToggleDetails: { index, details in
                    engine.toggleDetails(at: index, details: details)
                },
                onEffectiveContentWidthChange: { newWidth in
                    engine.updateEffectiveContentWidth(
                        newWidth,
                        markdown: text,
                        plugins: plugins,
                        theme: theme,
                        diagramRegistry: diagramRegistry,
                        imageLoadingPolicy: imageLoadingPolicy,
                        resourceLimits: resourceLimits,
                        appearance: appearance
                    )
                },
                onLinkTap: linkTapHandler,
                onCheckboxToggle: checkboxToggleHandler,
                theme: theme,
                textInteractionMode: textInteractionMode
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
                    imageLoadingPolicy: imageLoadingPolicy,
                    resourceLimits: resourceLimits,
                    appearance: appearance
                )
            }
            .onChange(of: renderInput) { _, newInput in
                engine.scheduleDebouncedRender(
                    markdown: newInput.text,
                    plugins: plugins,
                    theme: theme,
                    fallbackWidth: newInput.width,
                    diagramRegistry: diagramRegistry,
                    imageLoadingPolicy: imageLoadingPolicy,
                    resourceLimits: newInput.resourceLimits,
                    appearance: newInput.appearance
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

@available(iOS 14.0, macOS 11.0, *)
struct MarkdownParseKey: Equatable, Sendable {
    let text: String
    let resourceLimits: MarkdownParser.ResourceLimits
    let orderedPluginFingerprint: Int

    init(
        text: String,
        resourceLimits: MarkdownParser.ResourceLimits,
        orderedPluginFingerprint: Int
    ) {
        self.text = text
        self.resourceLimits = resourceLimits
        self.orderedPluginFingerprint = orderedPluginFingerprint
    }

    init(
        text: String,
        resourceLimits: MarkdownParser.ResourceLimits,
        plugins: [ASTPlugin]
    ) {
        self.init(
            text: text,
            resourceLimits: resourceLimits,
            orderedPluginFingerprint: ASTPluginFingerprint.make(for: plugins)
        )
    }
}

@available(iOS 14.0, macOS 11.0, *)
struct MarkdownRenderInput: Equatable {
    let width: CGFloat
    let appearance: MarkdownAppearance
    let parseKey: MarkdownParseKey
    let themeFingerprint: Int
    let diagramFingerprint: Int
    let imagePolicyFingerprint: Int

    var text: String { parseKey.text }
    var resourceLimits: MarkdownParser.ResourceLimits { parseKey.resourceLimits }

    init(
        text: String,
        width: CGFloat,
        resourceLimits: MarkdownParser.ResourceLimits,
        appearance: MarkdownAppearance,
        theme: Theme,
        plugins: [ASTPlugin],
        diagramRegistry: DiagramAdapterRegistry,
        imageLoadingPolicy: ImageLoadingPolicy
    ) {
        let parseKey = MarkdownParseKey(text: text, resourceLimits: resourceLimits, plugins: plugins)
        self.init(
            parseKey: parseKey,
            width: width,
            appearance: appearance,
            themeFingerprint: Self.themeFingerprint(theme, appearance: appearance),
            diagramFingerprint: diagramRegistry.cacheFingerprint,
            imagePolicyFingerprint: imageLoadingPolicy.cacheFingerprint
        )
    }

    init(
        parseKey: MarkdownParseKey,
        width: CGFloat,
        appearance: MarkdownAppearance,
        themeFingerprint: Int,
        diagramFingerprint: Int,
        imagePolicyFingerprint: Int
    ) {
        self.width = width
        self.appearance = appearance
        self.parseKey = parseKey
        self.themeFingerprint = themeFingerprint
        self.diagramFingerprint = diagramFingerprint
        self.imagePolicyFingerprint = imagePolicyFingerprint
    }

    static func themeFingerprint(_ theme: Theme, appearance: MarkdownAppearance) -> Int {
        var hasher = Hasher()
        theme.resolved(for: appearance).cacheFingerprint(into: &hasher)
        hasher.combine(appearance)
        return hasher.finalize()
    }
}

@available(iOS 14.0, macOS 11.0, *)
private extension MarkdownAppearance {
    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }
}
#endif
