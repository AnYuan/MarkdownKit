//
//  AppearanceAwareLayoutTests.swift
//  MarkdownKitTests
//
//  Tests for explicit, immutable, appearance-aware layout (Q10-P1).
//
//  Design goals verified:
//  1. Light/dark resolution of semantic Theme colors (label, separator…) differs.
//  2. Static (non-dynamic) colors are identical after resolution in both modes.
//  3. The shared LayoutCache hits within the same appearance variant, but a
//     dark-appearance solver never reuses entries produced by a light one.
//  4. LayoutResult.stableIdentity is unchanged across appearances; renderFingerprint
//     differs.
//  5. withStableIdentity preserves both appearance and renderFingerprint.
//  6. Attributed strings produced by the solver contain concrete colors.
//

import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class AppearanceAwareLayoutTests: XCTestCase {

    // MARK: - Platform color helpers

    /// Returns `(r, g, b, a)` components of a concrete color, or nil if the
    /// color cannot be decomposed (dynamic color that hasn't been resolved yet).
    private func components(of color: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #elseif canImport(AppKit)
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }

    private func componentsEqual(_ lhs: Color, _ rhs: Color) -> Bool {
        guard let l = components(of: lhs), let r = components(of: rhs) else { return false }
        return l.0 == r.0 && l.1 == r.1 && l.2 == r.2 && l.3 == r.3
    }

    private func assertColor(
        in attributedString: NSAttributedString,
        key: NSAttributedString.Key = .foregroundColor,
        at location: Int = 0,
        equals expected: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard attributedString.length > location else {
            XCTFail("Expected an attributed character at index \(location)", file: file, line: line)
            return
        }
        guard let color = attributedString.attribute(
            key,
            at: location,
            effectiveRange: nil
        ) as? Color else {
            XCTFail("Expected \(key.rawValue) color at index \(location)", file: file, line: line)
            return
        }

        XCTAssertNotNil(
            components(of: color),
            "\(key.rawValue) must be concrete",
            file: file,
            line: line
        )
        XCTAssertTrue(
            componentsEqual(color, expected),
            "\(key.rawValue) must match the explicitly resolved appearance color",
            file: file,
            line: line
        )
    }

    private func assertEverySupportedColor(
        in attributedString: NSAttributedString,
        equals expected: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for key in appearanceTestColorKeys {
            assertColor(
                in: attributedString,
                key: key,
                equals: expected,
                file: file,
                line: line
            )
        }
    }

    // MARK: - 1. Semantic color resolution differs light vs dark

    func testSemanticLabelColorDiffersLightVsDark() {
        #if canImport(UIKit)
        let platformLabel: Color = .label
        #elseif canImport(AppKit)
        let platformLabel: Color = .labelColor
        #endif
        let light = AppearanceColorResolver.resolveColor(platformLabel, for: .light)
        let dark  = AppearanceColorResolver.resolveColor(platformLabel, for: .dark)

        XCTAssertFalse(
            componentsEqual(light, dark),
            "Platform label color should resolve to different RGB values in light vs dark"
        )
    }

    // MARK: - 2. Static colors are stable across appearances

    func testStaticColorIsUnchangedAcrossAppearances() {
        let staticColor = Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0)
        let light = AppearanceColorResolver.resolveColor(staticColor, for: .light)
        let dark  = AppearanceColorResolver.resolveColor(staticColor, for: .dark)

        XCTAssertTrue(
            componentsEqual(light, dark),
            "A static RGBA color should be identical after resolution in both appearances"
        )
        guard let lc = components(of: light) else {
            XCTFail("Could not decompose resolved static color")
            return
        }
        XCTAssertEqual(lc.0, 0.2, accuracy: 0.001)
        XCTAssertEqual(lc.1, 0.6, accuracy: 0.001)
        XCTAssertEqual(lc.2, 0.9, accuracy: 0.001)
        XCTAssertEqual(lc.3, 1.0, accuracy: 0.001)
    }

    func testAttributedColorResolutionHandlesEverySupportedKeyInOnePass() {
        #if canImport(UIKit)
        let semanticColor: Color = .label
        #elseif canImport(AppKit)
        let semanticColor: Color = .labelColor
        #endif
        let colorKeys: [NSAttributedString.Key] = [
            .foregroundColor,
            .backgroundColor,
            .strokeColor,
            .underlineColor,
            .strikethroughColor
        ]
        let attributes = Dictionary(
            uniqueKeysWithValues: colorKeys.map { ($0, semanticColor as Any) }
        )
        let source = NSAttributedString(string: "x", attributes: attributes)
        let expected = AppearanceColorResolver.resolveColor(semanticColor, for: .dark)
        let resolved = AppearanceColorResolver.resolveColors(in: source, for: .dark)

        for key in colorKeys {
            let color = resolved.attribute(key, at: 0, effectiveRange: nil) as? Color
            XCTAssertNotNil(color)
            XCTAssertTrue(color.map { componentsEqual($0, expected) } ?? false)
        }

        let plain = NSAttributedString(string: "plain")
        XCTAssertIdentical(
            AppearanceColorResolver.resolveColors(in: plain, for: .dark),
            plain
        )
    }

    // MARK: - 3. Theme default text color resolves differently (semantic colors)

    func testDefaultThemeTextColorDiffersLightVsDark() {
        let theme = Theme.default
        let lightTheme = theme.resolved(for: .light)
        let darkTheme  = theme.resolved(for: .dark)

        XCTAssertFalse(
            componentsEqual(
                lightTheme.colors.textColor.foreground,
                darkTheme.colors.textColor.foreground
            ),
            "Theme.default text color (platform label) should differ between light and dark"
        )
    }

    func testDefaultThemeTableColorDiffersLightVsDark() {
        let theme = Theme.default
        let lightTheme = theme.resolved(for: .light)
        let darkTheme  = theme.resolved(for: .dark)

        // On both platforms the tableColor uses dynamic platform colors.
        // Foreground or background (or both) should differ.
        let fgEqual = componentsEqual(
            lightTheme.colors.tableColor.foreground,
            darkTheme.colors.tableColor.foreground
        )
        let bgEqual = componentsEqual(
            lightTheme.colors.tableColor.background,
            darkTheme.colors.tableColor.background
        )
        XCTAssertFalse(
            fgEqual && bgEqual,
            "Table color (platform separator/secondary background) should differ between light and dark"
        )
    }

    func testDefaultThemeRemainsEquatableAcrossConstruction() {
        XCTAssertEqual(Theme.default, Theme.default)
    }

    // MARK: - 4. LayoutCache hits within same appearance, misses across appearances

    func testCacheHitsWithinSameAppearance() async throws {
        let cache = LayoutCache()
        let markdown = "# Hello\n\nA paragraph."
        let doc1 = TestHelper.parse(markdown)

        let lightSolver = LayoutSolver(theme: .default, cache: cache, appearance: .light)
        _ = await lightSolver.solve(node: doc1, constrainedToWidth: 400)

        // Second solve with same appearance via a freshly parsed (same content) document.
        let doc2 = TestHelper.parse(markdown)
        cache.resetStatsForTesting()
        let lightSolver2 = LayoutSolver(theme: .default, cache: cache, appearance: .light)
        _ = await lightSolver2.solve(node: doc2, constrainedToWidth: 400)

        TestHelper.assertDebugCounter(
            cache.hitCountForTesting,
            greaterThan: 0,
            "Second light-appearance solve of identical content must hit the shared cache"
        )
    }

    func testCacheDoesNotReuseLightLayoutForDark() async throws {
        let cache = LayoutCache()
        let markdown = "# Hello\n\nA paragraph."
        let doc1 = TestHelper.parse(markdown)

        let lightSolver = LayoutSolver(theme: .default, cache: cache, appearance: .light)
        _ = await lightSolver.solve(node: doc1, constrainedToWidth: 400)

        let doc2 = TestHelper.parse(markdown)
        cache.resetStatsForTesting()
        let darkSolver = LayoutSolver(theme: .default, cache: cache, appearance: .dark)
        _ = await darkSolver.solve(node: doc2, constrainedToWidth: 400)

        XCTAssertEqual(
            cache.hitCountForTesting, 0,
            "Dark-appearance solver must not reuse any cache entries produced by the light-appearance solver"
        )
        TestHelper.assertDebugCounter(cache.missCountForTesting, greaterThan: 0)
    }

    // MARK: - 5. renderFingerprint differs between appearances

    func testRenderFingerprintDiffersAcrossAppearances() async throws {
        let markdown = "# Heading"
        let doc1 = TestHelper.parse(markdown)
        let doc2 = TestHelper.parse(markdown)

        let lightSolver = LayoutSolver(theme: .default, appearance: .light)
        let darkSolver  = LayoutSolver(theme: .default, appearance: .dark)

        let lightResult = await lightSolver.solve(node: doc1, constrainedToWidth: 400)
        let darkResult  = await darkSolver.solve(node: doc2, constrainedToWidth: 400)

        let lightChild = try XCTUnwrap(lightResult.children.first)
        let darkChild  = try XCTUnwrap(darkResult.children.first)

        XCTAssertNotEqual(
            lightChild.renderFingerprint,
            darkChild.renderFingerprint,
            "renderFingerprint must differ when appearance differs"
        )
    }

    // MARK: - 6. stableIdentity unchanged across appearances

    func testStableIdentityUnchangedAcrossAppearances() async throws {
        let markdown = "# Heading"
        let doc1 = TestHelper.parse(markdown)
        let doc2 = TestHelper.parse(markdown)

        let lightSolver = LayoutSolver(theme: .default, appearance: .light)
        let darkSolver  = LayoutSolver(theme: .default, appearance: .dark)

        let lightResult = await lightSolver.solve(node: doc1, constrainedToWidth: 400)
        let darkResult  = await darkSolver.solve(node: doc2, constrainedToWidth: 400)

        let lightChild = try XCTUnwrap(lightResult.children.first)
        let darkChild  = try XCTUnwrap(darkResult.children.first)

        XCTAssertEqual(
            lightChild.stableIdentity,
            darkChild.stableIdentity,
            "stableIdentity must be identical for the same content regardless of appearance"
        )
        XCTAssertNotEqual(
            lightChild.renderFingerprint,
            darkChild.renderFingerprint,
            "renderFingerprint must differ"
        )
    }

    // MARK: - 7. withStableIdentity preserves appearance and renderFingerprint

    func testWithStableIdentityPreservesAppearanceAndRenderFingerprint() {
        let node = DocumentNode(range: nil, children: [])
        let sentinel = 0xBEEF_DEAD
        let result = LayoutResult(
            node: node,
            size: .zero,
            appearance: .dark,
            renderFingerprint: sentinel
        )
        let newIdentity = StableNodeIdentity.topLevel(node: node, index: 99)
        let stamped = result.withStableIdentity(newIdentity)

        XCTAssertEqual(stamped.appearance, .dark)
        XCTAssertEqual(stamped.renderFingerprint, sentinel)
        XCTAssertEqual(stamped.stableIdentity, newIdentity)
    }

    // MARK: - 8. Public LayoutResult defaults and render payload hashing

    func testLayoutResultDefaultsToLightAppearanceAndHashesSize() {
        let node = DocumentNode(range: nil, children: [])
        let result = LayoutResult(node: node, size: .zero)
        let resized = LayoutResult(node: node, size: CGSize(width: 1, height: 0))
        XCTAssertEqual(result.appearance, .light)
        XCTAssertNotEqual(result.renderFingerprint, resized.renderFingerprint)
    }

    func testPublicInitializerRenderFingerprintTracksAttributedPayloadAndVariantDiff() {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "same node")])
        let first = LayoutResult(
            node: node,
            size: CGSize(width: 100, height: 20),
            attributedString: NSAttributedString(string: "first")
        )
        let second = LayoutResult(
            node: node,
            size: CGSize(width: 100, height: 20),
            attributedString: NSAttributedString(string: "second")
        )
        let normalizedFirst = LayoutResult.positionedTopLevelLayouts([first])
        let normalizedSecond = LayoutResult.positionedTopLevelLayouts([second])
        let previous = [normalizedFirst[0].stableIdentity: normalizedFirst[0]]

        XCTAssertEqual(normalizedFirst[0].stableIdentity, normalizedSecond[0].stableIdentity)
        XCTAssertNotEqual(normalizedFirst[0].renderFingerprint, normalizedSecond[0].renderFingerprint)
        XCTAssertEqual(
            LayoutResultVariantDiff.changedStableIdentities(
                previous: previous,
                next: normalizedSecond
            ),
            [normalizedFirst[0].stableIdentity]
        )
    }

    func testPublicInitializerCustomDrawGetsFreshRenderVariant() {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "drawn")])
        let first = LayoutResult(
            node: node,
            size: CGSize(width: 100, height: 20),
            customDraw: { _, _ in }
        )
        let second = LayoutResult(
            node: node,
            size: CGSize(width: 100, height: 20),
            customDraw: { _, _ in }
        )

        XCTAssertNotEqual(first.renderFingerprint, second.renderFingerprint)
    }

    // MARK: - 9. Attributed string colors are concrete after solving

    func testSolvedAttributedStringColorsAreConcrete() async throws {
        let markdown = "Hello **world** and `code`"
        let layout = await TestHelper.solveLayout(markdown, appearance: .light)
        let child = try XCTUnwrap(layout.children.first)
        guard let attrStr = child.attributedString else {
            XCTFail("Expected attributed string")
            return
        }

        var foundDynamic = false
        attrStr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let color = value as? Color else { return }
            if components(of: color) == nil {
                foundDynamic = true
            }
        }
        XCTAssertFalse(foundDynamic, "All foreground colors in solved attributed strings must be concrete (non-dynamic)")
    }

    // MARK: - 10. Builder and adapter boundaries resolve semantic colors

    func testBuilderBoundaryColorsResolveAcrossAppearancesAndSolverPaths() async throws {
        for appearance in [MarkdownAppearance.light, .dark] {
            let expected = AppearanceColorResolver.resolveColor(
                .platformSecondaryLabel,
                for: appearance
            )
            let codeDocument = TestHelper.parse("```swift\nlet x = 1\n```")
            let imageDocument = TestHelper.parse("![blocked](https://example.com/image.png)")
            let solver = LayoutSolver(appearance: appearance)

            let asyncCode = await solver.solve(node: codeDocument, constrainedToWidth: 400)
            let syncCode = solver.solveSync(node: codeDocument, constrainedToWidth: 400)
            let asyncImage = await solver.solve(node: imageDocument, constrainedToWidth: 400)
            let syncImage = solver.solveSync(node: imageDocument, constrainedToWidth: 400)

            for layout in [asyncCode, syncCode] {
                let attributedString = try XCTUnwrap(layout.children.first?.attributedString)
                XCTAssertTrue(attributedString.string.hasPrefix("SWIFT\n"))
                assertColor(in: attributedString, equals: expected)
            }

            for layout in [asyncImage, syncImage] {
                let attributedString = try XCTUnwrap(layout.children.first?.attributedString)
                XCTAssertEqual(attributedString.string, "[blocked]")
                assertColor(in: attributedString, equals: expected)
            }
        }
    }

    func testMathAdapterColorsResolveAcrossAppearancesAndSolverPaths() async throws {
        let node = MathNode(range: nil, style: .block, equation: "x")

        for appearance in [MarkdownAppearance.light, .dark] {
            let expected = AppearanceColorResolver.resolveColor(
                dynamicAppearanceTestColor,
                for: appearance
            )
            let solver = LayoutSolver(
                mathAdapter: AppearanceTestMathAdapter(),
                appearance: appearance
            )

            let asyncResult = await solver.solve(node: node, constrainedToWidth: 400)
            let syncResult = solver.solveSync(node: node, constrainedToWidth: 400)

            for result in [asyncResult, syncResult] {
                let attributedString = try XCTUnwrap(result.attributedString)
                XCTAssertEqual(attributedString.string, "math")
                assertEverySupportedColor(in: attributedString, equals: expected)
            }
        }
    }

    func testDiagramAdapterColorsResolveAcrossAppearances() async throws {
        let node = DiagramNode(range: nil, language: .mermaid, source: "graph TD")

        for appearance in [MarkdownAppearance.light, .dark] {
            var registry = DiagramAdapterRegistry()
            registry.register(AppearanceTestDiagramAdapter(), for: .mermaid)
            let solver = LayoutSolver(
                diagramRegistry: registry,
                appearance: appearance
            )
            let expected = AppearanceColorResolver.resolveColor(
                dynamicAppearanceTestColor,
                for: appearance
            )

            let result = await solver.solve(node: node, constrainedToWidth: 400)
            let attributedString = try XCTUnwrap(result.attributedString)

            XCTAssertEqual(attributedString.string, "diagram")
            assertEverySupportedColor(in: attributedString, equals: expected)
        }
    }

    // MARK: - 11. Solver-produced appearance field is correct

    func testSolverResultCarriesCorrectAppearance() async throws {
        let markdown = "paragraph"

        let lightLayout = await TestHelper.solveLayout(markdown, appearance: .light)
        let darkLayout  = await TestHelper.solveLayout(markdown, appearance: .dark)

        let lightChild = try XCTUnwrap(lightLayout.children.first)
        let darkChild  = try XCTUnwrap(darkLayout.children.first)

        XCTAssertEqual(lightChild.appearance, .light)
        XCTAssertEqual(darkChild.appearance, .dark)
    }

    func testEngineOneCallLayoutForwardsAppearance() async {
        let layout = await MarkdownKitEngine.layout(
            markdown: "paragraph",
            constrainedToWidth: 300,
            appearance: .dark
        )

        XCTAssertEqual(layout.appearance, .dark)
        XCTAssertEqual(layout.children.first?.appearance, .dark)
    }

    func testVariantDiffReconfiguresOnlyExistingChangedRenderVariants() {
        let node = TextNode(range: nil, text: "same")
        let original = LayoutResult(
            node: node,
            size: CGSize(width: 100, height: 20),
            renderFingerprint: 1
        )
        let appearanceChanged = LayoutResult(
            node: node,
            size: original.size,
            stableIdentity: original.stableIdentity,
            appearance: .dark
        )
        let renderVariantChanged = LayoutResult(
            node: node,
            size: original.size,
            stableIdentity: original.stableIdentity,
            renderFingerprint: 2
        )
        let sizeChanged = LayoutResult(
            node: node,
            size: CGSize(width: original.size.width, height: original.size.height + 1),
            stableIdentity: original.stableIdentity,
            renderFingerprint: 1
        )
        let unchanged = LayoutResult(
            node: node,
            size: original.size,
            stableIdentity: original.stableIdentity,
            renderFingerprint: 1
        )
        let newNode = TextNode(range: nil, text: "new")
        let inserted = LayoutResult(
            node: newNode,
            size: original.size,
            renderFingerprint: 3
        )
        let previous = [original.stableIdentity: original]

        XCTAssertEqual(
            LayoutResultVariantDiff.changedStableIdentities(
                previous: previous,
                next: [appearanceChanged, inserted]
            ),
            [original.stableIdentity]
        )
        XCTAssertEqual(
            LayoutResultVariantDiff.changedStableIdentities(
                previous: previous,
                next: [renderVariantChanged, inserted]
            ),
            [original.stableIdentity]
        )
        XCTAssertEqual(
            LayoutResultVariantDiff.changedStableIdentities(
                previous: previous,
                next: [sizeChanged, inserted]
            ),
            [original.stableIdentity]
        )
        XCTAssertTrue(
            LayoutResultVariantDiff.changedStableIdentities(
                previous: previous,
                next: [unchanged, inserted]
            ).isEmpty
        )
    }
}

private let appearanceTestColorKeys: [NSAttributedString.Key] = [
    .foregroundColor,
    .backgroundColor,
    .strokeColor,
    .underlineColor,
    .strikethroughColor
]

private var dynamicAppearanceTestColor: Color {
    #if canImport(UIKit)
    .label
    #elseif canImport(AppKit)
    .labelColor
    #endif
}

private func appearanceTestAttributedString(_ string: String) -> NSAttributedString {
    NSAttributedString(
        string: string,
        attributes: Dictionary(
            uniqueKeysWithValues: appearanceTestColorKeys.map {
                ($0, dynamicAppearanceTestColor as Any)
            }
        )
    )
}

private struct AppearanceTestMathAdapter: MathRenderingAdapter {
    func render(
        from node: MathNode,
        theme: Theme,
        contextFont: Font?
    ) async -> NSAttributedString {
        appearanceTestAttributedString("math")
    }

    func renderSync(
        from node: MathNode,
        theme: Theme,
        contextFont: Font?
    ) -> NSAttributedString {
        appearanceTestAttributedString("math")
    }
}

private struct AppearanceTestDiagramAdapter: DiagramRenderingAdapter {
    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        appearanceTestAttributedString("diagram")
    }
}
