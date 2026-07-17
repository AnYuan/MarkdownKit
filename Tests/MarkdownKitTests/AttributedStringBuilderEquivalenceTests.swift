import XCTest
import Markdown
import os
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Locks async/sync parity around the builder's shared flat render program.
/// Resource leaves intentionally differ by mode; all structural operations and
/// inherited attributes must remain equivalent.
final class AttributedStringBuilderEquivalenceTests: XCTestCase {

    private func solve(_ node: MarkdownNode) async -> (asyncResult: LayoutResult, syncResult: LayoutResult) {
        let solver = LayoutSolver()
        let asyncResult = await solver.solve(node: node, constrainedToWidth: 320)
        let syncResult = solver.solveSync(node: node, constrainedToWidth: 320)
        return (asyncResult, syncResult)
    }

    private func solve(_ markdown: String) async -> (asyncResult: LayoutResult, syncResult: LayoutResult) {
        let parser = MarkdownParser()
        let doc = parser.parse(markdown)
        return await solve(doc)
    }

    private func makeBuilder(
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        mathAdapter: any MathRenderingAdapter = RecordingMathAdapter(recorder: ResourceCallRecorder()),
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) -> AttributedStringBuilder {
        let theme = Theme.default
        return AttributedStringBuilder(
            theme: theme,
            highlighter: SplashHighlighter(theme: theme),
            diagramRegistry: diagramRegistry,
            mathAdapter: mathAdapter,
            imageLoadingPolicy: imageLoadingPolicy
        )
    }

    private func assertAttributedStringEqual(
        _ asyncString: NSAttributedString?,
        _ syncString: NSAttributedString?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let asyncString, let syncString else {
            XCTFail("Expected both async and sync attributed strings", file: file, line: line)
            return
        }

        let normalizedAsync = normalizedForEquality(asyncString)
        let normalizedSync = normalizedForEquality(syncString)
        XCTAssertTrue(
            normalizedAsync.isEqual(to: normalizedSync),
            "async/sync attributed strings drifted",
            file: file,
            line: line
        )
    }

    private func normalizedForEquality(_ string: NSAttributedString) -> NSAttributedString {
        let normalized = NSMutableAttributedString(attributedString: string)
        var replacements: [(NSRange, String)] = []
        normalized.enumerateAttribute(
            .markdownCheckbox,
            in: NSRange(location: 0, length: normalized.length)
        ) { value, range, _ in
            guard let data = value as? CheckboxInteractionData else { return }
            let sourceRange = data.range
            let source = sourceRange.lowerBound.source?.absoluteString ?? ""
            replacements.append((
                range,
                "\(data.isChecked)|\(sourceRange.lowerBound.line):\(sourceRange.lowerBound.column)"
                    + "-\(sourceRange.upperBound.line):\(sourceRange.upperBound.column)|\(source)"
            ))
        }
        for (range, replacement) in replacements {
            normalized.addAttribute(.markdownCheckbox, value: replacement, range: range)
        }
        return normalized
    }

    private func assertNodeAttributedStringEqual(
        _ node: MarkdownNode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (asyncResult: LayoutResult, syncResult: LayoutResult) {
        let results = await solve(node)
        assertAttributedStringEqual(
            results.asyncResult.attributedString,
            results.syncResult.attributedString,
            file: file,
            line: line
        )
        return results
    }

    /// Strings match exactly.
    private func assertStringEqual(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (asyncRoot, syncRoot) = await solve(markdown)
        XCTAssertEqual(asyncRoot.children.count, syncRoot.children.count, file: file, line: line)
        for (asyncChild, syncChild) in zip(asyncRoot.children, syncRoot.children) {
            let asyncString = asyncChild.attributedString?.string ?? ""
            let syncString = syncChild.attributedString?.string ?? ""
            XCTAssertEqual(
                asyncString,
                syncString,
                "async/sync string drifted for input: \(markdown.prefix(40))",
                file: file,
                line: line
            )
        }
    }

    /// Font of the first character matches — proxies "did we apply the same
    /// typography token for this node type".
    private func assertFontAtStartEqual(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (asyncRoot, syncRoot) = await solve(markdown)
        for (asyncChild, syncChild) in zip(asyncRoot.children, syncRoot.children) {
            guard let asyncStr = asyncChild.attributedString,
                  let syncStr = syncChild.attributedString,
                  asyncStr.length > 0,
                  syncStr.length > 0 else { continue }
            let asyncFont = asyncStr.attribute(.font, at: 0, effectiveRange: nil) as? Font
            let syncFont = syncStr.attribute(.font, at: 0, effectiveRange: nil) as? Font
            XCTAssertEqual(asyncFont, syncFont, file: file, line: line)
        }
    }

    // MARK: - Tests

    func testHeaderEquivalence() async {
        await assertStringEqual("# Heading One")
        await assertFontAtStartEqual("# Heading One")
        await assertStringEqual("## Heading Two")
        await assertStringEqual("### Heading Three")
    }

    func testParagraphEquivalence() async {
        await assertStringEqual("This is a simple paragraph.")
        await assertFontAtStartEqual("This is a simple paragraph.")
    }

    func testParagraphWithInlineFormattingEquivalence() async {
        await assertStringEqual("Plain *italic* **bold** ~~strike~~ `code` end.")
    }

    func testListEquivalence() async {
        await assertStringEqual("""
        - apple
        - banana
        - cherry
        """)
        await assertStringEqual("""
        1. one
        2. two
        3. three
        """)
    }

    func testNestedListTransformsFilteringAndSeparatorsRemainEquivalent() async throws {
        let nestedList = ListNode(
            range: nil,
            isOrdered: false,
            children: [
                TestBlockWrapper(children: [TextNode(range: nil, text: "filtered")]),
                ListItemNode(
                    range: nil,
                    children: [
                        ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Nested")])
                    ]
                )
            ]
        )
        let list = ListNode(
            range: nil,
            isOrdered: true,
            children: [
                TestInlineWrapper(children: [TextNode(range: nil, text: "filtered")]),
                ListItemNode(
                    range: nil,
                    children: [
                        ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Outer")]),
                        nestedList
                    ]
                ),
                TestBlockWrapper(children: [TextNode(range: nil, text: "filtered")]),
                ListItemNode(
                    range: nil,
                    children: [
                        ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Tail")])
                    ]
                )
            ]
        )

        let results = await assertNodeAttributedStringEqual(list)
        let string = try XCTUnwrap(results.syncResult.attributedString)
        XCTAssertEqual(string.string, "1. Outer\n• Nested\n2. Tail")

        let nestedRange = (string.string as NSString).range(of: "• Nested")
        let nestedStyle = try XCTUnwrap(
            string.attribute(.paragraphStyle, at: nestedRange.location, effectiveRange: nil)
                as? NSParagraphStyle
        )
        XCTAssertEqual(nestedStyle.firstLineHeadIndent, Theme.default.list.nestedIndentDelta)
        XCTAssertGreaterThan(nestedStyle.headIndent, nestedStyle.firstLineHeadIndent)

        let firstStyle = try XCTUnwrap(
            string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        let lastRange = (string.string as NSString).range(of: "2. Tail")
        let lastStyle = try XCTUnwrap(
            string.attribute(.paragraphStyle, at: lastRange.location, effectiveRange: nil)
                as? NSParagraphStyle
        )
        XCTAssertEqual(firstStyle.paragraphSpacing, 2)
        XCTAssertEqual(lastStyle.paragraphSpacing, Theme.default.typography.paragraph.paragraphSpacing)
    }

    func testTaskListEquivalence() async {
        await assertStringEqual("""
        - [x] done
        - [ ] todo
        """)
    }

    func testClosedAndOpenDetailsAttributedStringEquivalence() async {
        let summary = SummaryNode(
            range: nil,
            children: [
                TextNode(range: nil, text: "Build "),
                StrongNode(range: nil, children: [TextNode(range: nil, text: "status")])
            ]
        )
        let body = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Body")])

        let closed = DetailsNode(range: nil, isOpen: false, summary: summary, children: [body])
        let closedResults = await assertNodeAttributedStringEqual(closed)
        XCTAssertEqual(closedResults.syncResult.attributedString?.string, "▶ Build status")

        let open = DetailsNode(range: nil, isOpen: true, summary: summary, children: [body])
        let openResults = await assertNodeAttributedStringEqual(open)
        XCTAssertEqual(openResults.syncResult.attributedString?.string, "▼ Build status\nBody")
    }

    func testExplicitSummaryNodeAttributedStringEquivalence() async {
        let summary = SummaryNode(
            range: nil,
            children: [
                TextNode(range: nil, text: "Summary "),
                EmphasisNode(range: nil, children: [TextNode(range: nil, text: "row")])
            ]
        )

        let results = await assertNodeAttributedStringEqual(summary)
        XCTAssertEqual(results.syncResult.attributedString?.string, "Summary row")
    }

    func testNestedResourceFreeDetailsBodyAttributedStringEquivalence() async {
        let emptyBlock = TestBlockWrapper(children: [TextNode(range: nil, text: "ignored")])
        let nestedDetails = DetailsNode(
            range: nil,
            isOpen: true,
            summary: SummaryNode(range: nil, children: [TextNode(range: nil, text: "Nested")]),
            children: [ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Nested body")])]
        )
        let details = DetailsNode(
            range: nil,
            isOpen: true,
            summary: nil,
            children: [
                emptyBlock,
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "First body")]),
                nestedDetails
            ]
        )

        let results = await assertNodeAttributedStringEqual(details)
        XCTAssertEqual(
            results.syncResult.attributedString?.string,
            "▼ Details\nFirst body\n▼ Nested\nNested body"
        )
    }

    func testMixedDetailsAndBlockQuoteNewlinesAndAttributesRemainEquivalent() async throws {
        let quote = BlockQuoteNode(
            range: nil,
            children: [
                ParagraphNode(
                    range: nil,
                    children: [
                        TextNode(range: nil, text: "Quoted "),
                        StrongNode(range: nil, children: [TextNode(range: nil, text: "body")])
                    ]
                ),
                TestBlockWrapper(children: [TextNode(range: nil, text: "filtered")])
            ]
        )
        let details = DetailsNode(
            range: nil,
            isOpen: true,
            summary: SummaryNode(range: nil, children: [TextNode(range: nil, text: "Mixed")]),
            children: [
                quote,
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "After")])
            ]
        )

        let results = await assertNodeAttributedStringEqual(details)
        let string = try XCTUnwrap(results.syncResult.attributedString)
        XCTAssertEqual(string.string, "▼ Mixed\n┃ Quoted body\n\n\nAfter")

        let barRange = (string.string as NSString).range(of: Theme.default.blockQuote.barCharacter)
        let quoteRange = (string.string as NSString).range(of: "Quoted body")
        XCTAssertNotEqual(
            string.attribute(.foregroundColor, at: barRange.location, effectiveRange: nil) as? Color,
            string.attribute(.foregroundColor, at: quoteRange.location, effectiveRange: nil) as? Color
        )
        XCTAssertEqual(
            string.attribute(.paragraphStyle, at: barRange.location, effectiveRange: nil)
                as? NSParagraphStyle,
            string.attribute(.paragraphStyle, at: quoteRange.location, effectiveRange: nil)
                as? NSParagraphStyle
        )
    }

    func testBlockQuoteNestedListUsesChildLocalSeparatorState() async throws {
        let list = ListNode(
            range: nil,
            isOrdered: false,
            children: [
                ListItemNode(
                    range: nil,
                    children: [
                        ParagraphNode(
                            range: nil,
                            children: [TextNode(range: nil, text: "item")]
                        )
                    ]
                )
            ]
        )
        let quote = BlockQuoteNode(
            range: nil,
            children: [
                ParagraphNode(
                    range: nil,
                    children: [TextNode(range: nil, text: "text")]
                ),
                list
            ]
        )

        let results = await assertNodeAttributedStringEqual(quote)

        XCTAssertEqual(results.syncResult.attributedString?.string, "┃ text\n• item\n")
    }

    func testTaskPrefixesCarryInteractionDataAndAccessibilityState() async {
        await assertTaskPrefix(state: .checked, expectedChecked: true)
        await assertTaskPrefix(state: .unchecked, expectedChecked: false)
    }

    func testSyncInlineDefaultRecursivelyFlattensCustomInlineNodes() async {
        let paragraph = ParagraphNode(
            range: nil,
            children: [
                TextNode(range: nil, text: "before "),
                TestInlineWrapper(children: [
                    TestInlineWrapper(children: [TextNode(range: nil, text: "wrapped")])
                ]),
                TestBlockWrapper(children: [TextNode(range: nil, text: " hidden block ")]),
                TextNode(range: nil, text: " after")
            ]
        )

        let results = await assertNodeAttributedStringEqual(paragraph)
        XCTAssertEqual(results.syncResult.attributedString?.string, "before wrapped after")
    }

    func testDeepUnknownInlineRecursionPreservesInheritedAttributes() async throws {
        let destination = "https://example.com/deep"
        let paragraph = ParagraphNode(
            range: nil,
            children: [
                StrongNode(
                    range: nil,
                    children: [
                        TestInlineWrapper(children: [
                            EmphasisNode(
                                range: nil,
                                children: [
                                    TestInlineWrapper(children: [
                                        StrikethroughNode(
                                            range: nil,
                                            children: [
                                                LinkNode(
                                                    range: nil,
                                                    destination: destination,
                                                    title: nil,
                                                    children: [
                                                        TestInlineWrapper(children: [
                                                            TextNode(range: nil, text: "deep")
                                                        ])
                                                    ]
                                                )
                                            ]
                                        )
                                    ])
                                ]
                            )
                        ])
                    ]
                )
            ]
        )

        let results = await assertNodeAttributedStringEqual(paragraph)
        let string = try XCTUnwrap(results.syncResult.attributedString)
        let expectedFont = FontTraitResolver.adding(
            .italic,
            to: FontTraitResolver.adding(.bold, to: Theme.default.typography.paragraph.font)
        )

        XCTAssertEqual(string.attribute(.font, at: 0, effectiveRange: nil) as? Font, expectedFont)
        XCTAssertEqual(
            string.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertEqual(
            string.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertEqual(
            string.attribute(.link, at: 0, effectiveRange: nil) as? URL,
            URL(string: destination)
        )
    }

    func testClosedDetailsDoesNotMaterializeBodyResources() async {
        let recorder = ResourceCallRecorder()
        var registry = DiagramAdapterRegistry()
        registry.register(RecordingDiagramAdapter(recorder: recorder), for: .mermaid)
        let builder = makeBuilder(
            diagramRegistry: registry,
            mathAdapter: RecordingMathAdapter(recorder: recorder)
        )
        let details = DetailsNode(
            range: nil,
            isOpen: false,
            summary: SummaryNode(range: nil, children: [TextNode(range: nil, text: "Closed")]),
            children: [
                MathNode(range: nil, style: .block, equation: "hidden-math"),
                DiagramNode(range: nil, language: .mermaid, source: "hidden-diagram")
            ]
        )

        let asyncString = await builder.buildString(for: details, constrainedToWidth: 320)
        XCTAssertEqual(asyncString.string, "▶ Closed")
        XCTAssertEqual(recorder.snapshot(), [])

        let syncString = builder.buildStringSync(for: details, constrainedToWidth: 320)
        XCTAssertEqual(syncString.string, "▶ Closed")
        XCTAssertEqual(recorder.snapshot(), [])
    }

    func testAsyncResourcesMaterializeSequentiallyInSourceOrder() async {
        let recorder = ResourceCallRecorder()
        var registry = DiagramAdapterRegistry()
        registry.register(RecordingDiagramAdapter(recorder: recorder), for: .mermaid)
        let builder = makeBuilder(
            diagramRegistry: registry,
            mathAdapter: RecordingMathAdapter(recorder: recorder)
        )
        let details = DetailsNode(
            range: nil,
            isOpen: true,
            summary: SummaryNode(range: nil, children: [TextNode(range: nil, text: "Resources")]),
            children: [
                MathNode(range: nil, style: .block, equation: "first"),
                DiagramNode(range: nil, language: .mermaid, source: "second"),
                ParagraphNode(
                    range: nil,
                    children: [
                        TextNode(range: nil, text: "third "),
                        MathNode(range: nil, style: .inline, equation: "third")
                    ]
                )
            ]
        )

        let string = await builder.buildString(for: details, constrainedToWidth: 320)

        XCTAssertEqual(string.string, "▼ Resources\n<A:first>\n<D:second>\nthird <A:third>")
        XCTAssertEqual(
            recorder.snapshot(),
            [
                "math-start:first",
                "math-end:first",
                "diagram-start:second",
                "diagram-end:second",
                "math-start:third",
                "math-end:third"
            ]
        )
    }

    func testAsyncAndSyncResourceDifferencesRemainExplicit() async throws {
        let recorder = ResourceCallRecorder()
        var registry = DiagramAdapterRegistry()
        registry.register(RecordingDiagramAdapter(recorder: recorder), for: .mermaid)
        let builder = makeBuilder(
            diagramRegistry: registry,
            mathAdapter: RecordingMathAdapter(recorder: recorder),
            imageLoadingPolicy: .trusted
        )

        let math = MathNode(range: nil, style: .block, equation: "x")
        let asyncMath = await builder.buildString(for: math, constrainedToWidth: 320)
        XCTAssertEqual(asyncMath.string, "<A:x>")
        XCTAssertEqual(
            builder.buildStringSync(for: math, constrainedToWidth: 320).string,
            "<S:x>"
        )

        let diagram = DiagramNode(range: nil, language: .mermaid, source: "graph")
        let asyncDiagram = await builder.buildString(for: diagram, constrainedToWidth: 320)
        XCTAssertEqual(asyncDiagram.string, "<D:graph>")
        XCTAssertEqual(
            builder.buildStringSync(for: diagram, constrainedToWidth: 320).string,
            ""
        )

        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("builder-resource-\(UUID().uuidString).png")
        try TestHelper.onePixelPNGData().write(to: fixtureURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let image = ImageNode(
            range: nil,
            source: fixtureURL.absoluteString,
            altText: "fixture",
            title: nil
        )
        let paragraph = ParagraphNode(range: nil, children: [image])
        let asyncImage = await builder.buildString(for: paragraph, constrainedToWidth: 320)
        let syncImage = builder.buildStringSync(for: paragraph, constrainedToWidth: 320)

        XCTAssertNotNil(asyncImage.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertEqual(syncImage.string, "[fixture]")
        XCTAssertNil(syncImage.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testRecursiveInlineFallbackDoesNotChangeUnsupportedBlockContexts() async {
        let topLevelInline = await solve(
            TestInlineWrapper(children: [TextNode(range: nil, text: "inline")])
        )
        XCTAssertEqual(topLevelInline.asyncResult.attributedString?.length, 0)
        XCTAssertEqual(topLevelInline.syncResult.attributedString?.length, 0)

        let unknownBlock = await solve(
            TestBlockWrapper(children: [TextNode(range: nil, text: "block")])
        )
        XCTAssertEqual(unknownBlock.asyncResult.attributedString?.length, 0)
        XCTAssertEqual(unknownBlock.syncResult.attributedString?.length, 0)

        let orphan = await solve(
            ListItemNode(
                range: nil,
                children: [ParagraphNode(range: nil, children: [TextNode(range: nil, text: "item")])]
            )
        )
        XCTAssertEqual(orphan.asyncResult.attributedString?.length, 0)
        XCTAssertEqual(orphan.syncResult.attributedString?.length, 0)
    }

    func testBlockQuoteEquivalence() async {
        await assertStringEqual("> First quote\n> Second line")
    }

    func testCodeBlockEquivalence() async {
        await assertStringEqual("""
        ```swift
        let x = 1
        print(x)
        ```
        """)
    }

    func testTableEquivalence() async {
        // iOS routes tables through `customDraw` (no attributedString),
        // macOS goes through `TableAttributedStringBuilder`. Either way the
        // sync and async paths build the same way.
        await assertStringEqual("""
        | A | B |
        |---|---|
        | 1 | 2 |
        """)
    }

    func testLinkAndInlineCodeInsideParagraphEquivalence() async {
        await assertStringEqual("See [Apple](https://apple.com) and call `print()`.")
    }

    private func assertTaskPrefix(
        state: CheckboxState,
        expectedChecked: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let itemRange = SourceLocation(line: 3, column: 2, source: nil)
            ..< SourceLocation(line: 3, column: 14, source: nil)
        let listRange = SourceLocation(line: 2, column: 1, source: nil)
            ..< SourceLocation(line: 4, column: 1, source: nil)
        let item = ListItemNode(
            range: itemRange,
            checkbox: state,
            children: [
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Task")])
            ]
        )
        let list = ListNode(range: listRange, isOrdered: false, children: [item])
        let results = await assertNodeAttributedStringEqual(list, file: file, line: line)

        for result in [results.asyncResult, results.syncResult] {
            guard let string = result.attributedString else {
                XCTFail("Expected task attributed string", file: file, line: line)
                continue
            }

            var effectiveRange = NSRange()
            guard let data = string.attribute(
                .markdownCheckbox,
                at: 0,
                effectiveRange: &effectiveRange
            ) as? CheckboxInteractionData else {
                XCTFail("Expected checkbox interaction data", file: file, line: line)
                continue
            }

            XCTAssertEqual(data.isChecked, expectedChecked, file: file, line: line)
            XCTAssertEqual(data.range, itemRange, file: file, line: line)
            XCTAssertEqual(
                effectiveRange,
                NSRange(location: 0, length: themePrefixLength(for: state)),
                file: file,
                line: line
            )
            XCTAssertEqual(result.accessibility.taskCheckboxState, state, file: file, line: line)
        }
    }

    private func themePrefixLength(for state: CheckboxState) -> Int {
        let prefix: String
        switch state {
        case .checked:
            prefix = Theme.default.list.checkedCharacter
        case .unchecked:
            prefix = Theme.default.list.uncheckedCharacter
        case .none:
            prefix = Theme.default.list.bulletCharacter
        }
        return (prefix as NSString).length
    }
}

private struct TestInlineWrapper: InlineNode {
    let id = UUID()
    let range: SourceRange? = nil
    let children: [MarkdownNode]
    let contentFingerprint: Int

    init(children: [MarkdownNode]) {
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TestInlineWrapper",
            children: children
        )
    }
}

private struct TestBlockWrapper: BlockNode {
    let id = UUID()
    let range: SourceRange? = nil
    let children: [MarkdownNode]
    let contentFingerprint: Int

    init(children: [MarkdownNode]) {
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TestBlockWrapper",
            children: children
        )
    }
}

private final class ResourceCallRecorder: Sendable {
    private let calls = OSAllocatedUnfairLock(initialState: [String]())

    func record(_ call: String) {
        calls.withLock { $0.append(call) }
    }

    func snapshot() -> [String] {
        calls.withLock { $0 }
    }
}

private struct RecordingMathAdapter: MathRenderingAdapter {
    let recorder: ResourceCallRecorder

    func render(from node: MathNode, theme: Theme, contextFont: Font?) async -> NSAttributedString {
        recorder.record("math-start:\(node.equation)")
        try? await Task.sleep(for: .milliseconds(5))
        recorder.record("math-end:\(node.equation)")
        return NSAttributedString(string: "<A:\(node.equation)>")
    }

    func renderSync(from node: MathNode, theme: Theme, contextFont: Font?) -> NSAttributedString {
        recorder.record("math-sync:\(node.equation)")
        return NSAttributedString(string: "<S:\(node.equation)>")
    }
}

private struct RecordingDiagramAdapter: DiagramRenderingAdapter {
    let recorder: ResourceCallRecorder

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        recorder.record("diagram-start:\(source)")
        try? await Task.sleep(for: .milliseconds(5))
        recorder.record("diagram-end:\(source)")
        return NSAttributedString(string: "<D:\(source)>")
    }
}
