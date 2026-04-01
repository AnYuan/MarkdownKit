import XCTest
import Markdown
@testable import MarkdownKit

final class SendableTests: XCTestCase {
    func testCoreMarkdownASTNodesAreSendable() {
        func requireSendable<T: Sendable>(_: T) {}

        let text = TextNode(range: nil, text: "Hello")
        let paragraph = ParagraphNode(range: nil, children: [text])
        let listItem = ListItemNode(range: nil, checkbox: .checked, children: [paragraph])
        let list = ListNode(range: nil, isOrdered: false, children: [listItem])
        let header = HeaderNode(range: nil, level: 2, children: [text])
        let table = TableNode(
            range: nil,
            columnAlignments: [.left, .center, .right],
            children: [
                TableHeadNode(
                    range: nil,
                    children: [
                        TableRowNode(
                            range: nil,
                            children: [
                                TableCellNode(range: nil, children: [text])
                            ]
                        )
                    ]
                )
            ]
        )
        let math = MathNode(range: nil, style: .inline, equation: "E=mc^2")
        let details = DetailsNode(
            range: nil,
            isOpen: true,
            summary: SummaryNode(range: nil, children: [text]),
            children: [paragraph]
        )
        let document = DocumentNode(
            range: nil,
            children: [header, paragraph, list, table, math, details]
        )

        requireSendable(text)
        requireSendable(paragraph)
        requireSendable(listItem)
        requireSendable(list)
        requireSendable(header)
        requireSendable(table)
        requireSendable(math)
        requireSendable(details)
        requireSendable(document)
    }

    func testMarkdownNodeExistentialsRemainSendable() {
        func requireSendable<T: Sendable>(_: T) {}

        let range: SourceRange? = nil
        let text = TextNode(range: range, text: "Hello")
        let paragraph = ParagraphNode(range: range, children: [text])
        let nodes: [MarkdownNode] = [text, paragraph]

        requireSendable(range)
        requireSendable(nodes)
    }
}
