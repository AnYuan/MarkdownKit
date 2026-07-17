import XCTest
@testable import MarkdownKit

#if canImport(SwiftUI)
private struct FingerprintedPlugin: ASTPlugin {
    let value: Int

    func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        nodes
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
        hasher.combine(value)
    }
}

private struct FingerprintedDiagramAdapter: DiagramRenderingAdapter {
    let value: Int

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        nil
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
        hasher.combine(value)
    }
}

@available(iOS 14.0, macOS 11.0, *)
final class MarkdownRenderInputTests: XCTestCase {
    private let limits = MarkdownParser.ResourceLimits.default

    func testRenderInputTracksEveryRenderingDimension() {
        let base = makeInput()

        XCTAssertNotEqual(base, makeInput(text: "changed"))
        XCTAssertNotEqual(base, makeInput(width: 401))
        XCTAssertNotEqual(
            base,
            makeInput(resourceLimits: MarkdownParser.ResourceLimits(
                maximumInputBytes: limits.maximumInputBytes + 1,
                maximumNestingDepth: limits.maximumNestingDepth
            ))
        )
        XCTAssertNotEqual(base, makeInput(appearance: .dark))
        XCTAssertNotEqual(base, makeInput(theme: theme(textColor: .systemRed)))
        XCTAssertNotEqual(base, makeInput(plugins: [FingerprintedPlugin(value: 1)]))
        XCTAssertNotEqual(
            base,
            makeInput(diagramRegistry: registry(adapterValue: 1))
        )
        XCTAssertNotEqual(base, makeInput(imageLoadingPolicy: .remoteHTTPS))
    }

    func testPluginFingerprintTracksConfigurationAndOrder() {
        XCTAssertNotEqual(
            makeInput(plugins: [FingerprintedPlugin(value: 1)]),
            makeInput(plugins: [FingerprintedPlugin(value: 2)])
        )
        XCTAssertNotEqual(
            makeInput(plugins: [
                FingerprintedPlugin(value: 1),
                FingerprintedPlugin(value: 2)
            ]),
            makeInput(plugins: [
                FingerprintedPlugin(value: 2),
                FingerprintedPlugin(value: 1)
            ])
        )
    }

    func testDiagramFingerprintTracksAdapterConfiguration() {
        XCTAssertNotEqual(
            makeInput(diagramRegistry: registry(adapterValue: 1)),
            makeInput(diagramRegistry: registry(adapterValue: 2))
        )
    }

    private func makeInput(
        text: String = "markdown",
        width: CGFloat = 400,
        resourceLimits: MarkdownParser.ResourceLimits? = nil,
        appearance: MarkdownAppearance = .light,
        theme: Theme = .default,
        plugins: [ASTPlugin] = [],
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) -> MarkdownRenderInput {
        MarkdownRenderInput(
            text: text,
            width: width,
            resourceLimits: resourceLimits ?? limits,
            appearance: appearance,
            theme: theme,
            plugins: plugins,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: imageLoadingPolicy
        )
    }

    private func registry(adapterValue: Int) -> DiagramAdapterRegistry {
        DiagramAdapterRegistry(adapters: [
            .mermaid: FingerprintedDiagramAdapter(value: adapterValue)
        ])
    }

    private func theme(textColor: Color) -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: Theme.Colors(
                textColor: ColorToken(foreground: textColor),
                codeColor: base.colors.codeColor,
                inlineCodeColor: base.colors.inlineCodeColor,
                tableColor: base.colors.tableColor,
                linkColor: base.colors.linkColor,
                blockQuoteColor: base.colors.blockQuoteColor,
                thematicBreakColor: base.colors.thematicBreakColor
            ),
            codeBlock: base.codeBlock,
            blockQuote: base.blockQuote,
            list: base.list,
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }
}
#endif
