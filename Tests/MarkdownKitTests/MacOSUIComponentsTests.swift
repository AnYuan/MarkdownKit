import XCTest
@testable import MarkdownKit

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

@MainActor
final class MacOSUIComponentsTests: XCTestCase {

    // MARK: - MarkdownItemView

    func testLoadViewCreatesNSView() {
        let item = MarkdownItemView()
        item.loadView()
        XCTAssertNotNil(item.view)
        XCTAssertTrue(item.view.wantsLayer, "View should have wantsLayer set to true")
    }

    func testConfigureAddsTextViewSubview() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Hello")])
        let attrStr = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 20),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 1, "Configure should add exactly one subview")
        XCTAssertTrue(item.view.subviews[0] is NSTextView, "Subview should be NSTextView")
    }

    func testConfigureWithCodeBlockSetsBackgroundAndCornerRadius() {
        let item = MarkdownItemView()
        item.loadView()

        let node = CodeBlockNode(range: nil, language: "swift", code: "let x = 1")
        let attrStr = NSAttributedString(string: "let x = 1", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 40),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 1)

        guard let textView = item.view.subviews[0] as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }

        XCTAssertTrue(textView.drawsBackground, "Code block text view should draw background")
        XCTAssertEqual(textView.layer?.cornerRadius, 6, "Code block should have corner radius of 6")
    }

    func testConfigureWithNilAttributedStringAddsNoSubview() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 0),
            attributedString: nil
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 0,
            "Nil attributed string should not add any subview")
    }

    func testConfigureWithEmptyAttributedStringAddsNoSubview() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [])
        let attrStr = NSAttributedString(string: "")
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 0),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 0,
            "Empty attributed string should not add any subview")
    }

    func testPrepareForReuseRemovesHostedView() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Hello")])
        let attrStr = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 20),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 1)

        item.prepareForReuse()
        XCTAssertEqual(item.view.subviews.count, 0,
            "prepareForReuse should remove all hosted views")
    }

    func testReconfigureReplacesHostedView() {
        let item = MarkdownItemView()
        item.loadView()

        let node1 = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "First")])
        let attrStr1 = NSAttributedString(string: "First", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layout1 = LayoutResult(node: node1, size: CGSize(width: 300, height: 20), attributedString: attrStr1)

        let node2 = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Second")])
        let attrStr2 = NSAttributedString(string: "Second", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layout2 = LayoutResult(node: node2, size: CGSize(width: 300, height: 20), attributedString: attrStr2)

        item.configure(with: layout1)
        XCTAssertEqual(item.view.subviews.count, 1)

        item.configure(with: layout2)
        XCTAssertEqual(item.view.subviews.count, 1,
            "Reconfigure should replace (not stack) hosted views")

        guard let textView = item.view.subviews[0] as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertTrue(textView.textStorage?.string.contains("Second") ?? false,
            "Reconfigured text view should show new content")
    }

    // MARK: - MarkdownCollectionView

    func testInitializesWithScrollViewSubview() {
        let view = MarkdownCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        XCTAssertGreaterThanOrEqual(view.subviews.count, 1,
            "MarkdownCollectionView should contain at least one subview (scrollView)")
        XCTAssertTrue(view.subviews[0] is NSScrollView,
            "First subview should be NSScrollView")
    }
}
#endif
