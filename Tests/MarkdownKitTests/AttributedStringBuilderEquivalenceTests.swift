import XCTest
import Markdown
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// `AttributedStringBuilder.buildString` (async) and `buildStringSync` are
/// near-duplicate ~150-line implementations. They MUST agree on output for
/// every non-async-dependent node type (everything except math / images /
/// diagrams, which call into adapters whose behavior differs between sync
/// and async modes).
///
/// These tests lock in that equivalence so the planned async/sync unification
/// refactor (Phase 6.2 follow-up) doesn't silently break parity.
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
