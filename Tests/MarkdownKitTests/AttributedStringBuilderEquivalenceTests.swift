import XCTest
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

    private func solve(_ markdown: String) async -> (asyncResult: LayoutResult, syncResult: LayoutResult) {
        let parser = MarkdownParser()
        let solver = LayoutSolver()
        let doc = parser.parse(markdown)
        let asyncResult = await solver.solve(node: doc, constrainedToWidth: 320)
        let syncResult = solver.solveSync(node: doc, constrainedToWidth: 320)
        return (asyncResult, syncResult)
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
}
