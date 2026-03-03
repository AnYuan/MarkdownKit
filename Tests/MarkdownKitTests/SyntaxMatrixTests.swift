import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class SyntaxMatrixTests: XCTestCase {

    private let widths: [CGFloat] = [280, 560, 920]

    private var pluginChain: [ASTPlugin] {
        [
            DetailsExtractionPlugin(),
            DiagramExtractionPlugin(),
            MathExtractionPlugin()
        ]
    }

    func testSyntaxMatrixAcrossWidthsWithPluginPipeline() async throws {
        let localImagePath = try makeTemporaryPNGFilePath()
        let relativeImageFixture = try makeRelativePNGFilePath()
        defer { try? FileManager.default.removeItem(atPath: localImagePath) }
        defer { try? FileManager.default.removeItem(at: relativeImageFixture.absoluteURL) }

        let fixtures = makeFixtures(
            localImagePath: localImagePath,
            relativeLocalImagePath: relativeImageFixture.relativePath
        )

        for fixture in fixtures {
            let document = TestHelper.parse(fixture.markdown, plugins: pluginChain)

            for kind in fixture.requiredNodeKinds {
                XCTAssertTrue(
                    containsNode(kind, in: document),
                    "[\(fixture.id)] expected AST to contain node kind \(kind.rawValue)"
                )
            }

            assertASTSemantics(for: fixture, document: document)

            var baselineTopLevelCount: Int?
            let solver = LayoutSolver()

            for width in widths {
                let layout = await solver.solve(node: document, constrainedToWidth: width)
                let messagePrefix = "[\(fixture.id)] [width=\(Int(width))]"

                XCTAssertEqual(
                    layout.children.count,
                    document.children.count,
                    "\(messagePrefix) layout top-level child count should match AST top-level child count"
                )
                XCTAssertGreaterThan(
                    layout.children.count,
                    0,
                    "\(messagePrefix) non-empty fixture should produce top-level layout children"
                )

                if let baselineTopLevelCount {
                    XCTAssertEqual(
                        layout.children.count,
                        baselineTopLevelCount,
                        "\(messagePrefix) top-level child count should be stable across widths"
                    )
                } else {
                    baselineTopLevelCount = layout.children.count
                }

                assertFiniteGeometry(in: layout, maxWidth: width, fixtureID: fixture.id)
                assertNonEmptyRenderedOutput(in: layout, fixtureID: fixture.id, width: width)
                assertLayoutSemantics(for: fixture, layout: layout, width: width)
            }
        }
    }

    private func assertASTSemantics(for fixture: SyntaxFixture, document: DocumentNode) {
        switch fixture.id {
        case "headers":
            let headerCount = countNodes(of: .header, in: document)
            XCTAssertEqual(headerCount, 3, "[headers] expected exactly 3 header nodes")

        case "task-list":
            let items = collectNodes(of: ListItemNode.self, in: document)
            let checked = items.filter { $0.checkbox == .checked }
            let unchecked = items.filter { $0.checkbox == .unchecked }
            XCTAssertFalse(checked.isEmpty, "[task-list] expected at least one checked item")
            XCTAssertFalse(unchecked.isEmpty, "[task-list] expected at least one unchecked item")

        case "ordered-list":
            let ordered = collectNodes(of: ListNode.self, in: document).filter(\.isOrdered)
            XCTAssertFalse(ordered.isEmpty, "[ordered-list] expected at least one ordered list node")

        case "details-closed":
            guard let details = collectNodes(of: DetailsNode.self, in: document).first else {
                XCTFail("[details-closed] expected details node")
                return
            }
            XCTAssertFalse(details.isOpen, "[details-closed] expected details node to be closed")

        case "details-open":
            guard let details = collectNodes(of: DetailsNode.self, in: document).first else {
                XCTFail("[details-open] expected details node")
                return
            }
            XCTAssertTrue(details.isOpen, "[details-open] expected details node to be open")

        case "diagrams":
            let diagrams = collectNodes(of: DiagramNode.self, in: document)
            XCTAssertEqual(diagrams.count, 4, "[diagrams] expected 4 diagram nodes (all supported languages)")

        case "math":
            let mathNodes = collectNodes(of: MathNode.self, in: document)
            XCTAssertGreaterThanOrEqual(mathNodes.count, 2, "[math] expected at least 2 math nodes")

        default:
            break
        }
    }

    private func assertLayoutSemantics(for fixture: SyntaxFixture, layout: LayoutResult, width: CGFloat) {
        let text = combinedRenderedText(from: layout)

        switch fixture.id {
        case "links":
            XCTAssertTrue(hasLinkAttribute(in: layout, url: "https://openai.com"), "[links] expected URL link attribute")

        case "inline-code":
            XCTAssertTrue(text.contains("let x = 42"), "[inline-code] rendered output should contain inline code text")

        case "code-block":
            XCTAssertTrue(text.contains("SWIFT"), "[code-block] expected language label")
            XCTAssertTrue(text.contains("let x = 42"), "[code-block] expected code content")

        case "task-list":
            XCTAssertTrue(text.contains("☑"), "[task-list] expected checked symbol")
            XCTAssertTrue(text.contains("☐"), "[task-list] expected unchecked symbol")

        case "ordered-list":
            XCTAssertTrue(text.contains("1."), "[ordered-list] expected ordered prefix 1.")
            XCTAssertTrue(text.contains("2."), "[ordered-list] expected ordered prefix 2.")

        case "table":
            XCTAssertTrue(usesNativeTextTableBlocks(in: layout), "[table] expected NSTextTableBlock-based rendering")
            XCTAssertFalse(text.contains("|---"), "[table] should not expose markdown separator syntax")
            XCTAssertTrue(text.contains("Feature"), "[table] expected header text in rendered output")
            XCTAssertTrue(text.contains("Parsing"), "[table] expected body text in rendered output")

        case "blockquote-and-hr":
            XCTAssertTrue(text.contains("┃"), "[blockquote-and-hr] expected quote bar glyph")
            XCTAssertTrue(text.contains(String(repeating: "─", count: 40)), "[blockquote-and-hr] expected thematic break line")

        case "details-closed":
            XCTAssertTrue(text.contains("▶ Build status"), "[details-closed] expected closed disclosure indicator")
            XCTAssertFalse(text.contains("Hidden body"), "[details-closed] hidden body should not be rendered")

        case "details-open":
            XCTAssertTrue(text.contains("▼ Build status"), "[details-open] expected open disclosure indicator")
            XCTAssertTrue(text.contains("Visible body"), "[details-open] open body should be rendered")

        case "diagrams":
            XCTAssertTrue(text.contains("MERMAID"), "[diagrams] expected mermaid fallback label")
            XCTAssertTrue(text.contains("GEOJSON"), "[diagrams] expected geojson fallback label")
            XCTAssertTrue(text.contains("TOPOJSON"), "[diagrams] expected topojson fallback label")
            XCTAssertTrue(text.contains("STL"), "[diagrams] expected stl fallback label")

        case "math":
            let hasMathAttachment = containsAttachment(in: layout)
            let hasFallbackText = text.contains("x^2") || text.contains("a^2 + b^2 = c^2")
            XCTAssertTrue(hasMathAttachment || hasFallbackText, "[math] expected rendered math attachment or text fallback")

        case "image-local", "image-local-relative":
            XCTAssertTrue(containsAttachment(in: layout), "[image-local] expected inline image attachment")

        case "image-fallback":
            XCTAssertTrue(text.contains("[Missing Image]"), "[image-fallback] expected alt-text fallback")

        default:
            break
        }

        XCTAssertGreaterThan(width, 0, "[\(fixture.id)] width should be positive")
    }

    private func assertFiniteGeometry(in layout: LayoutResult, maxWidth: CGFloat, fixtureID: String) {
        func walk(_ node: LayoutResult, depth: Int) {
            let prefix = "[\(fixtureID)] [depth=\(depth)]"
            XCTAssertTrue(node.size.width.isFinite, "\(prefix) width must be finite")
            XCTAssertTrue(node.size.height.isFinite, "\(prefix) height must be finite")
            XCTAssertGreaterThanOrEqual(node.size.width, 0, "\(prefix) width must be non-negative")
            XCTAssertGreaterThanOrEqual(node.size.height, 0, "\(prefix) height must be non-negative")
            XCTAssertLessThanOrEqual(node.size.width, maxWidth + 1, "\(prefix) width should respect constraints")

            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }

        walk(layout, depth: 0)
    }

    private func assertNonEmptyRenderedOutput(in layout: LayoutResult, fixtureID: String, width: CGFloat) {
        let renderedCount = allAttributedStrings(in: layout)
            .map(\.length)
            .reduce(0, +)

        XCTAssertGreaterThan(
            renderedCount,
            0,
            "[\(fixtureID)] [width=\(Int(width))] expected non-empty rendered attributed output"
        )
    }

    private func allAttributedStrings(in layout: LayoutResult) -> [NSAttributedString] {
        var result: [NSAttributedString] = []
        if let attributed = layout.attributedString, attributed.length > 0 {
            result.append(attributed)
        }

        for child in layout.children {
            result.append(contentsOf: allAttributedStrings(in: child))
        }

        return result
    }

    private func combinedRenderedText(from layout: LayoutResult) -> String {
        allAttributedStrings(in: layout).map(\.string).joined(separator: "\n")
    }

    private func containsAttachment(in layout: LayoutResult) -> Bool {
        for attributed in allAttributedStrings(in: layout) {
            var found = false
            attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
                if value is NSTextAttachment {
                    found = true
                    stop.pointee = true
                }
            }
            if found {
                return true
            }
        }
        return false
    }

    private func hasLinkAttribute(in layout: LayoutResult, url: String) -> Bool {
        for attributed in allAttributedStrings(in: layout) {
            var found = false
            attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
                if let linkURL = value as? URL, linkURL.absoluteString == url {
                    found = true
                    stop.pointee = true
                }
            }
            if found {
                return true
            }
        }
        return false
    }

    private func usesNativeTextTableBlocks(in layout: LayoutResult) -> Bool {
        for attributed in allAttributedStrings(in: layout) {
            var found = false
            attributed.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
                guard let style = value as? NSParagraphStyle else { return }
                if style.textBlocks.contains(where: { $0 is NSTextTableBlock }) {
                    found = true
                    stop.pointee = true
                }
            }
            if found {
                return true
            }
        }
        return false
    }

    private func containsNode(_ kind: NodeKind, in root: MarkdownNode) -> Bool {
        if node(root, matches: kind) {
            return true
        }

        for child in traversalChildren(of: root) where containsNode(kind, in: child) {
            return true
        }

        return false
    }

    private func countNodes(of kind: NodeKind, in root: MarkdownNode) -> Int {
        var total = node(root, matches: kind) ? 1 : 0
        for child in traversalChildren(of: root) {
            total += countNodes(of: kind, in: child)
        }
        return total
    }

    private func node(_ node: MarkdownNode, matches kind: NodeKind) -> Bool {
        switch kind {
        case .header: return node is HeaderNode
        case .paragraph: return node is ParagraphNode
        case .strong: return node is StrongNode
        case .emphasis: return node is EmphasisNode
        case .strikethrough: return node is StrikethroughNode
        case .link: return node is LinkNode
        case .image: return node is ImageNode
        case .inlineCode: return node is InlineCodeNode
        case .codeBlock: return node is CodeBlockNode
        case .list: return node is ListNode
        case .listItem: return node is ListItemNode
        case .table: return node is TableNode
        case .tableHead: return node is TableHeadNode
        case .tableBody: return node is TableBodyNode
        case .tableRow: return node is TableRowNode
        case .tableCell: return node is TableCellNode
        case .math: return node is MathNode
        case .blockQuote: return node is BlockQuoteNode
        case .thematicBreak: return node is ThematicBreakNode
        case .details: return node is DetailsNode
        case .summary: return node is SummaryNode
        case .diagram: return node is DiagramNode
        }
    }

    private func collectNodes<T: MarkdownNode>(of type: T.Type, in root: MarkdownNode) -> [T] {
        var result: [T] = []

        if let typed = root as? T {
            result.append(typed)
        }

        for child in traversalChildren(of: root) {
            result.append(contentsOf: collectNodes(of: type, in: child))
        }

        return result
    }

    private func traversalChildren(of node: MarkdownNode) -> [MarkdownNode] {
        if let details = node as? DetailsNode, let summary = details.summary {
            return [summary] + details.children
        }
        return node.children
    }

    private func makeFixtures(
        localImagePath: String,
        relativeLocalImagePath: String
    ) -> [SyntaxFixture] {
        [
            SyntaxFixture(
                id: "headers",
                markdown: """
                # H1

                ## H2

                ### H3

                body text
                """,
                requiredNodeKinds: [.header, .paragraph]
            ),
            SyntaxFixture(
                id: "inline-formatting",
                markdown: "Normal **bold** *italic* ~~struck~~ text.",
                requiredNodeKinds: [.paragraph, .strong, .emphasis, .strikethrough]
            ),
            SyntaxFixture(
                id: "links",
                markdown: "See [OpenAI](https://openai.com).",
                requiredNodeKinds: [.paragraph, .link]
            ),
            SyntaxFixture(
                id: "inline-code",
                markdown: "Use `let x = 42` in Swift.",
                requiredNodeKinds: [.paragraph, .inlineCode]
            ),
            SyntaxFixture(
                id: "code-block",
                markdown: """
                ```swift
                let x = 42
                print(x)
                ```
                """,
                requiredNodeKinds: [.codeBlock]
            ),
            SyntaxFixture(
                id: "task-list",
                markdown: """
                - [x] parser baseline
                - [ ] diagram rendering
                """,
                requiredNodeKinds: [.list, .listItem]
            ),
            SyntaxFixture(
                id: "ordered-list",
                markdown: """
                1. first
                2. second
                """,
                requiredNodeKinds: [.list, .listItem]
            ),
            SyntaxFixture(
                id: "table",
                markdown: """
                | Feature | Status | Priority |
                |:--------|:------:|--------:|
                | Parsing | Done   | High    |
                | Layout  | WIP    | Medium  |
                """,
                requiredNodeKinds: [.table, .tableHead, .tableBody, .tableRow, .tableCell]
            ),
            SyntaxFixture(
                id: "blockquote-and-hr",
                markdown: """
                > quoted paragraph

                ---
                """,
                requiredNodeKinds: [.blockQuote, .thematicBreak]
            ),
            SyntaxFixture(
                id: "details-closed",
                markdown: """
                <details>
                <summary>Build status</summary>

                Hidden body
                </details>
                """,
                requiredNodeKinds: [.details, .summary]
            ),
            SyntaxFixture(
                id: "details-open",
                markdown: """
                <details open>
                <summary>Build status</summary>

                Visible body
                </details>
                """,
                requiredNodeKinds: [.details, .summary]
            ),
            SyntaxFixture(
                id: "diagrams",
                markdown: """
                ```mermaid
                graph TD
                A-->B
                ```

                ```geojson
                { "type": "FeatureCollection", "features": [] }
                ```

                ```topojson
                { "type": "Topology", "objects": {} }
                ```

                ```stl
                solid Demo
                  facet normal 0 0 1
                endsolid Demo
                ```
                """,
                requiredNodeKinds: [.diagram]
            ),
            SyntaxFixture(
                id: "math",
                markdown: """
                Inline math: $x^2$.

                ```math
                a^2 + b^2 = c^2
                ```
                """,
                requiredNodeKinds: [.math]
            ),
            SyntaxFixture(
                id: "image-local",
                markdown: "![Local Image](\(localImagePath))",
                requiredNodeKinds: [.image]
            ),
            SyntaxFixture(
                id: "image-local-relative",
                markdown: "![Local Relative Image](\(relativeLocalImagePath))",
                requiredNodeKinds: [.image]
            ),
            SyntaxFixture(
                id: "image-fallback",
                markdown: "![Missing Image](./Tests/Fixtures/does-not-exist.png)",
                requiredNodeKinds: [.image]
            )
        ]
    }

    private func makeTemporaryPNGFilePath() throws -> String {
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8B9n0AAAAASUVORK5CYII="

        guard let data = Data(base64Encoded: base64PNG) else {
            throw MatrixFixtureError.failedToDecodePNG
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdownkit-matrix-\(UUID().uuidString).png")

        try data.write(to: url, options: .atomic)
        return url.path
    }

    private func makeRelativePNGFilePath() throws -> (relativePath: String, absoluteURL: URL) {
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8B9n0AAAAASUVORK5CYII="

        guard let data = Data(base64Encoded: base64PNG) else {
            throw MatrixFixtureError.failedToDecodePNG
        }

        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let fixtureDir = cwdURL.appendingPathComponent(".build/markdownkit-matrix-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)

        let fileURL = fixtureDir.appendingPathComponent("matrix-\(UUID().uuidString).png")
        try data.write(to: fileURL, options: .atomic)

        let relativePath = fileURL.path.replacingOccurrences(of: cwdURL.path + "/", with: "")
        return (relativePath, fileURL)
    }
}

private struct SyntaxFixture {
    let id: String
    let markdown: String
    let requiredNodeKinds: [NodeKind]
}

private enum NodeKind: String {
    case header
    case paragraph
    case strong
    case emphasis
    case strikethrough
    case link
    case image
    case inlineCode
    case codeBlock
    case list
    case listItem
    case table
    case tableHead
    case tableBody
    case tableRow
    case tableCell
    case math
    case blockQuote
    case thematicBreak
    case details
    case summary
    case diagram
}

private enum MatrixFixtureError: Error {
    case failedToDecodePNG
}
