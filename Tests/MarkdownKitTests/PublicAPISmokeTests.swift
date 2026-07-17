import XCTest
import Foundation
import CoreGraphics
import MarkdownKit

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

private final class ImmutableSmokeAutolinkResolver: MarkdownAutolinkResolver {
    let baseURLString: String

    init(baseURLString: String = "https://example.test") {
        self.baseURLString = baseURLString
    }

    func resolveMention(username: String) -> URL? {
        URL(string: "\(baseURLString)/users/\(username)")
    }

    func resolveReference(reference: String) -> URL? {
        let normalized = reference.hasPrefix("#") ? String(reference.dropFirst()) : reference
        return URL(string: "\(baseURLString)/references/\(normalized)")
    }

    func resolveCommit(sha: String) -> URL? {
        URL(string: "\(baseURLString)/commits/\(sha)")
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(baseURLString)
    }
}

private struct StrongSmokeTokenPlugin: ASTPlugin, Sendable {
    func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        AST.transform(nodes) { node in
            guard let text = node as? TextNode, text.text == "SMOKE_TOKEN" else {
                return .unchanged
            }
            return .replace(StrongNode(
                range: text.range,
                children: [TextNode(range: nil, text: "rewritten")]
            ))
        }
    }
}

private struct SmokeDiagramAdapter: DiagramRenderingAdapter {
    let prefix: String

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        NSAttributedString(string: "\(prefix):\(language.rawValue):\(source)")
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(prefix)
    }
}

private struct SmokeMathAdapter: MathRenderingAdapter {
    let prefix: String

    func render(
        from node: MathNode,
        theme: Theme,
        contextFont: MarkdownKit.Font?
    ) async -> NSAttributedString {
        NSAttributedString(string: "\(prefix):\(node.equation)")
    }

    func renderSync(
        from node: MathNode,
        theme: Theme,
        contextFont: MarkdownKit.Font?
    ) -> NSAttributedString {
        NSAttributedString(string: "\(prefix):\(node.equation)")
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(prefix)
    }
}

#if canImport(SwiftUI)
private func requireSwiftUIView<V: View>(_: V) {}
#endif

final class PublicAPISmokeTests: XCTestCase {
    func testEngineOneCallLayout() async {
        let layout = await MarkdownKitEngine.layout(
            markdown: "# Public API\n\nHello **MarkdownKit**.",
            constrainedToWidth: 480
        )

        XCTAssertTrue(layout.node is DocumentNode)
        XCTAssertGreaterThan(layout.children.count, 0)
    }

    func testExplicitParserSolverAndTypedOutcome() async throws {
        let parser = MarkdownKitEngine.makeParser()
        let solver = MarkdownKitEngine.makeLayoutSolver()

        let outcome = parser.parseOutcome("## Explicit Pipeline")
        guard case .parsed(let document, let diagnostics) = outcome else {
            return XCTFail("Expected parseOutcome to produce a document")
        }

        XCTAssertTrue(diagnostics.isEmpty)
        let layout = await solver.solve(node: document, constrainedToWidth: 360)
        XCTAssertEqual(layout.children.count, document.children.count)
    }

    func testResourceLimitsRejectOversizedInput() {
        let limits = MarkdownParser.ResourceLimits(maximumInputBytes: 3, maximumNestingDepth: 4)
        let parser = MarkdownKitEngine.makeParser(resourceLimits: limits)

        let outcome = parser.parseOutcome("abcd")

        guard case .rejected(let diagnostic) = outcome else {
            return XCTFail("Expected oversized input to be rejected")
        }
        XCTAssertEqual(diagnostic, .inputTooLarge(actualBytes: 4, maximumBytes: 3))
        XCTAssertTrue(outcome.isRejected)
        XCTAssertNil(outcome.document)
    }

    func testThemeAppearanceAndImageLoadingPolicyConstruction() async {
        let theme = Theme.default
        let customPolicy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["HTTPS"],
            allowsLocalFileURLs: true,
            allowsRelativeFilePaths: true,
            maximumResponseBytes: -1
        )
        let solver = MarkdownKitEngine.makeLayoutSolver(
            theme: theme,
            imageLoadingPolicy: customPolicy,
            appearance: .dark
        )
        let document = DocumentNode(range: nil, children: [
            ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Themed")])
        ])

        let layout = await solver.solve(node: document, constrainedToWidth: 240)

        XCTAssertEqual(layout.appearance, .dark)
        XCTAssertEqual(customPolicy.allowedRemoteSchemes, ["https"])
        XCTAssertTrue(customPolicy.allowsLocalFileURLs)
        XCTAssertTrue(customPolicy.allowsRelativeFilePaths)
        XCTAssertEqual(customPolicy.maximumResponseBytes, 0)
        XCTAssertTrue(ImageLoadingPolicy.default.allowedRemoteSchemes.isEmpty)
        XCTAssertFalse(ImageLoadingPolicy.default.allowsLocalFileURLs)
        XCTAssertFalse(ImageLoadingPolicy.default.allowsRelativeFilePaths)
        XCTAssertEqual(ImageLoadingPolicy.disabled.maximumResponseBytes, 0)
        XCTAssertEqual(ImageLoadingPolicy.remoteHTTPS.allowedRemoteSchemes, ["https"])
        XCTAssertTrue(ImageLoadingPolicy.trusted.allowsRelativeFilePaths)
    }

    func testAutolinkResolverAndGitHubPluginWiring() throws {
        let resolver = ImmutableSmokeAutolinkResolver()
        let plugins = MarkdownKitEngine.defaultPlugins(
            autolinkResolver: resolver,
            includeGitHubAutolinks: true
        )
        let parser = MarkdownKitEngine.makeParser(
            autolinkResolver: resolver,
            includeGitHubAutolinks: true
        )

        XCTAssertTrue(plugins.contains { $0 is GitHubAutolinkPlugin })

        let document = parser.parse("Hello @octocat")
        let paragraph = try XCTUnwrap(document.children.first as? ParagraphNode)
        let link = try XCTUnwrap(paragraph.children.compactMap { $0 as? LinkNode }.first)
        XCTAssertEqual(link.destination, "https://example.test/users/octocat")
    }

    func testCustomASTPluginUsesPublicRewriteModel() throws {
        let parser = MarkdownParser(plugins: [StrongSmokeTokenPlugin()])
        let document = parser.parse("SMOKE_TOKEN")

        let paragraph = try XCTUnwrap(document.children.first as? ParagraphNode)
        let strong = try XCTUnwrap(paragraph.children.first as? StrongNode)
        let rewrittenText = try XCTUnwrap(strong.children.first as? TextNode)
        XCTAssertEqual(rewrittenText.text, "rewritten")
    }

    func testDiagramAdapterRegistryFlow() async throws {
        var registry = DiagramAdapterRegistry()
        registry.register(SmokeDiagramAdapter(prefix: "diagram"), for: .mermaid)
        XCTAssertNotNil(registry.adapter(for: .mermaid))

        let solver = LayoutSolver(diagramRegistry: registry)
        let node = DiagramNode(range: nil, language: .mermaid, source: "graph TD; A-->B")
        let layout = await solver.solve(node: node, constrainedToWidth: 400)

        XCTAssertEqual(layout.attributedString?.string, "diagram:mermaid:graph TD; A-->B")
    }

    func testCustomMathAdapterIsAcceptedByLayoutSolver() async {
        let solver = LayoutSolver(mathAdapter: SmokeMathAdapter(prefix: "math"))
        let node = MathNode(range: nil, style: .inline, equation: "x^2")
        let layout = await solver.solve(node: node, constrainedToWidth: 300)

        XCTAssertEqual(layout.attributedString?.string, "math:x^2")
    }

    #if canImport(SwiftUI)
    @available(iOS 14.0, macOS 11.0, *)
    @MainActor
    func testMarkdownViewModifiersCompileWithExplicitSwiftUIImport() {
        let view = MarkdownView(text: "[link](https://example.test)\n- [ ] Task")
            .onLinkTap { _ in }
            .onCheckboxToggle { _ in }
            .textInteractionMode(.selectableNative)

        requireSwiftUIView(view)
    }
    #endif

    #if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
    @MainActor
    func testDirectMarkdownCollectionViewIntegration() {
        let first = makeManualCollectionLayout(text: "UIKit")
        let second = makeManualCollectionLayout(text: "UIKit")
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        view.textInteractionMode = .asyncReadOnly
        view.layouts = [first, second]

        XCTAssertEqual(view.layouts.count, 2)
    }
    #elseif canImport(SwiftUI) && canImport(AppKit) && !targetEnvironment(macCatalyst)
    @MainActor
    func testDirectMarkdownCollectionViewIntegration() {
        let first = makeManualCollectionLayout(text: "AppKit")
        let second = makeManualCollectionLayout(text: "AppKit")
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        view.textInteractionMode = .asyncReadOnly
        view.layouts = [first, second]

        XCTAssertEqual(view.layouts.count, 2)
    }
    #endif

    private func makeManualCollectionLayout(text: String) -> LayoutResult {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: text)])
        return LayoutResult(
            node: node,
            size: CGSize(width: 320, height: 44),
            attributedString: NSAttributedString(string: text),
            children: [],
            customDraw: nil,
            appearance: .light
        )
    }
}
