import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class iOSAccessibilityTests: XCTestCase {

    // MARK: - Paragraph

    func testCellTraitsForParagraph() {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Hello world")])
        let attrStr = NSAttributedString(string: "Hello world")
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 40), attributedString: attrStr)

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertEqual(cell.accessibilityTraits, .staticText)
        XCTAssertEqual(cell.accessibilityLabel, "Hello world")
        XCTAssertNil(cell.accessibilityValue)
    }

    // MARK: - Image

    func testCellTraitsForImage() {
        let node = ImageNode(range: nil, source: "https://example.com/img.png", altText: "photo of sunset", title: nil)
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 200))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertTrue(cell.accessibilityTraits.contains(.image))
        XCTAssertEqual(cell.accessibilityLabel, "Image: photo of sunset")
    }

    // MARK: - Details (closed)

    func testCellTraitsForDetailsClosed() {
        let summary = SummaryNode(range: nil, children: [TextNode(range: nil, text: "Build status")])
        let node = DetailsNode(range: nil, isOpen: false, summary: summary, children: [])
        let attrStr = NSAttributedString(string: "▶ Build status")
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 30), attributedString: attrStr)

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertTrue(cell.accessibilityTraits.contains(.button))
        XCTAssertTrue(cell.accessibilityLabel?.starts(with: "Collapsible Section:") ?? false)
        XCTAssertEqual(cell.accessibilityValue, "Collapsed")
    }

    // MARK: - Details (open)

    func testCellTraitsForDetailsOpen() {
        let summary = SummaryNode(range: nil, children: [TextNode(range: nil, text: "Build status")])
        let node = DetailsNode(range: nil, isOpen: true, summary: summary, children: [])
        let attrStr = NSAttributedString(string: "▼ Build status")
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 30), attributedString: attrStr)

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.accessibilityValue, "Expanded")
    }

    // MARK: - Code Block

    func testCellTraitsForCodeBlock() {
        let node = CodeBlockNode(range: nil, language: "swift", code: "let x = 1")
        let attrStr = NSAttributedString(string: "let x = 1")
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 60), attributedString: attrStr)

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertEqual(cell.accessibilityTraits, .staticText)
        XCTAssertEqual(cell.accessibilityLabel, "let x = 1")
    }

    // MARK: - Checkbox list items

    func testCellValueForCheckedListItem() {
        let node = ListItemNode(range: nil, checkbox: .checked, children: [
            ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Done")])
        ])
        let attrStr = NSAttributedString(string: "☑ Done")
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 30), attributedString: attrStr)

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.accessibilityValue, "Checked")
    }

    func testCellValueForUncheckedListItem() {
        let node = ListItemNode(range: nil, checkbox: .unchecked, children: [
            ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Todo")])
        ])
        let attrStr = NSAttributedString(string: "☐ Todo")
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 30), attributedString: attrStr)

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.accessibilityValue, "Unchecked")
    }

    // MARK: - Reuse clears accessibility

    func testPrepareForReuseClearsAccessibility() {
        let node = ImageNode(range: nil, source: "https://example.com/img.png", altText: "photo", title: nil)
        let layout = LayoutResult(node: node, size: CGSize(width: 300, height: 200))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertTrue(cell.isAccessibilityElement)
        XCTAssertNotNil(cell.accessibilityLabel)

        cell.prepareForReuse()

        XCTAssertFalse(cell.isAccessibilityElement)
        XCTAssertNil(cell.accessibilityLabel)
        XCTAssertNil(cell.accessibilityValue)
        XCTAssertEqual(cell.accessibilityTraits, .none)
    }
}
#endif
