import XCTest
@testable import MarkdownKit

/// A test plugin that replaces all TextNode contents with "REDACTED".
private struct RedactPlugin: ASTPlugin {
    func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        return nodes.map { node in
            if let text = node as? TextNode {
                return TextNode(range: text.range, text: "REDACTED")
            }
            if let header = node as? HeaderNode {
                let newChildren = visit(header.children)
                return HeaderNode(range: header.range, level: header.level, children: newChildren)
            }
            if let para = node as? ParagraphNode {
                let newChildren = visit(para.children)
                return ParagraphNode(range: para.range, children: newChildren)
            }
            return node
        }
    }
}

final class ASTPluginTests: XCTestCase {

    func testParserWithNoPlugins() throws {
        let parser = MarkdownParser(plugins: [])
        let doc = parser.parse("Hello")
        let para = doc.children[0] as? ParagraphNode
        let text = para?.children[0] as? TextNode
        XCTAssertEqual(text?.text, "Hello")
    }

    func testSinglePluginTransformsAST() throws {
        let doc = TestHelper.parse("# Secret Title", plugins: [RedactPlugin()])
        let header = doc.children[0] as? HeaderNode
        let text = header?.children[0] as? TextNode
        XCTAssertEqual(text?.text, "REDACTED")
    }

    func testMultiplePluginsChainedInOrder() throws {
        let doc = TestHelper.parse("Hello World", plugins: [RedactPlugin(), RedactPlugin()])
        let para = doc.children[0] as? ParagraphNode
        let text = para?.children[0] as? TextNode
        XCTAssertEqual(text?.text, "REDACTED")
    }

    func testPluginReceivesTopLevelNodes() throws {
        var receivedNodeTypes: [String] = []

        struct InspectorPlugin: ASTPlugin {
            let onVisit: ([MarkdownNode]) -> Void
            func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
                onVisit(nodes)
                return nodes
            }
        }

        let plugin = InspectorPlugin { nodes in
            receivedNodeTypes = nodes.map { String(describing: type(of: $0)) }
        }

        _ = TestHelper.parse("# Title\nParagraph text", plugins: [plugin])
        XCTAssertTrue(receivedNodeTypes.contains("HeaderNode"))
        XCTAssertTrue(receivedNodeTypes.contains("ParagraphNode"))
    }

    func testPluginCanInjectMathNode() throws {
        struct MathInjectorPlugin: ASTPlugin {
            func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
                var result: [MarkdownNode] = []
                for node in nodes {
                    if node is ParagraphNode {
                        result.append(MathNode(range: nil, style: .inline, equation: "E=mc^2"))
                    } else {
                        result.append(node)
                    }
                }
                return result
            }
        }

        let doc = TestHelper.parse("Some text", plugins: [MathInjectorPlugin()])
        let math = doc.children[0] as? MathNode
        XCTAssertNotNil(math)
        XCTAssertEqual(math?.equation, "E=mc^2")
        XCTAssertEqual(math?.style, .inline)
    }

    // MARK: - Plugin Edge Cases

    func testPluginReturningEmptyArrayProducesEmptyDocument() {
        struct EmptyPlugin: ASTPlugin {
            func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] { [] }
        }

        let doc = TestHelper.parse("# Hello\nWorld", plugins: [EmptyPlugin()])
        XCTAssertEqual(doc.children.count, 0,
            "Plugin returning empty array should produce empty document")
    }

    func testPluginDuplicatingNodesDoublesChildren() {
        struct DuplicatePlugin: ASTPlugin {
            func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
                return nodes + nodes
            }
        }

        let doc = TestHelper.parse("Hello", plugins: [DuplicatePlugin()])
        XCTAssertEqual(doc.children.count, 2,
            "Duplicating plugin should double the children count")
    }

    func testAllThreeBuiltInPluginsChained() {
        let markdown = """
        Inline math: $x^2$

        ```mermaid
        graph TD
        A-->B
        ```

        <details>
        <summary>Info</summary>

        Body text.
        </details>
        """

        let plugins: [ASTPlugin] = [
            MathExtractionPlugin(),
            DiagramExtractionPlugin(),
            DetailsExtractionPlugin()
        ]
        let doc = TestHelper.parse(markdown, plugins: plugins)

        func findNode<T: MarkdownNode>(_ type: T.Type, in node: MarkdownNode) -> Bool {
            if node is T { return true }
            return node.children.contains { findNode(type, in: $0) }
        }

        XCTAssertTrue(findNode(MathNode.self, in: doc), "Should find MathNode")
        XCTAssertTrue(findNode(DiagramNode.self, in: doc), "Should find DiagramNode")
        XCTAssertTrue(findNode(DetailsNode.self, in: doc), "Should find DetailsNode")
    }

    func testPluginOrderMathBeforeDiagram() {
        let markdown = """
        $E=mc^2$

        ```mermaid
        graph TD
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [
            MathExtractionPlugin(),
            DiagramExtractionPlugin()
        ])

        func findNode<T: MarkdownNode>(_ type: T.Type, in node: MarkdownNode) -> Bool {
            if node is T { return true }
            return node.children.contains { findNode(type, in: $0) }
        }

        XCTAssertTrue(findNode(MathNode.self, in: doc), "Math-first order should produce MathNode")
        XCTAssertTrue(findNode(DiagramNode.self, in: doc), "Math-first order should produce DiagramNode")
    }

    func testPluginOrderDiagramBeforeMath() {
        let markdown = """
        $E=mc^2$

        ```mermaid
        graph TD
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [
            DiagramExtractionPlugin(),
            MathExtractionPlugin()
        ])

        func findNode<T: MarkdownNode>(_ type: T.Type, in node: MarkdownNode) -> Bool {
            if node is T { return true }
            return node.children.contains { findNode(type, in: $0) }
        }

        XCTAssertTrue(findNode(MathNode.self, in: doc), "Diagram-first order should produce MathNode")
        XCTAssertTrue(findNode(DiagramNode.self, in: doc), "Diagram-first order should produce DiagramNode")
    }

    func testPluginDoesNotModifyUnrelatedNodes() {
        let doc = TestHelper.parse("Just a paragraph.", plugins: [DiagramExtractionPlugin()])
        XCTAssertEqual(doc.children.count, 1)
        XCTAssertTrue(doc.children[0] is ParagraphNode,
            "DiagramExtractionPlugin should not modify unrelated paragraph nodes")
    }

    func testPluginPreservesNodeIDs() {
        // Parse without plugins first to establish baseline count
        let withoutPlugins = TestHelper.parse("# Hello\nWorld")
        let countBefore = withoutPlugins.children.count

        // Parse with a passthrough plugin
        struct PassthroughPlugin: ASTPlugin {
            func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] { nodes }
        }

        let withPlugin = TestHelper.parse("# Hello\nWorld", plugins: [PassthroughPlugin()])
        XCTAssertEqual(withPlugin.children.count, countBefore,
            "Passthrough plugin should not change children count")

        // Each node should still have a unique ID
        let ids = withPlugin.children.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "All node IDs should be unique")
    }

    func testDetailsAndDiagramPluginComposition() {
        let markdown = """
        <details open>
        <summary>Diagrams</summary>

        ```mermaid
        graph TD
        A-->B
        ```
        </details>
        """

        let doc = TestHelper.parse(markdown, plugins: [
            DetailsExtractionPlugin(),
            DiagramExtractionPlugin()
        ])

        guard let details = doc.children.first as? DetailsNode else {
            XCTFail("Expected DetailsNode as first child")
            return
        }

        XCTAssertTrue(details.isOpen, "Details should be open")
        XCTAssertNotNil(details.summary, "Details should have summary")

        let hasDiagram = details.children.contains { $0 is DiagramNode }
        XCTAssertTrue(hasDiagram, "Details body should contain DiagramNode")
    }
}
