import XCTest
@testable import MyMarkdown

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class UIComponentsPlatformTests: XCTestCase {

    // MARK: - AsyncImageView

    func testAsyncImageViewConfigureWithNonImageNodeIsNoop() async throws {
        let textNode = TextNode(range: nil, text: "not an image")
        let layout = LayoutResult(node: textNode, size: CGSize(width: 100, height: 50))

        let view = AsyncImageView(frame: .zero)
        view.configure(with: layout)

        // Should not crash, frame should be set
        XCTAssertEqual(view.frame.size, CGSize(width: 100, height: 50))
    }

    func testAsyncImageViewConfigureWithNilSourceIsNoop() async throws {
        let imageNode = ImageNode(range: nil, source: nil, altText: nil, title: nil)
        let layout = LayoutResult(node: imageNode, size: CGSize(width: 100, height: 50))

        let view = AsyncImageView(frame: .zero)
        view.configure(with: layout)

        XCTAssertEqual(view.frame.size, CGSize(width: 100, height: 50))
    }

    func testAsyncImageViewConfigureWithInvalidURLIsNoop() async throws {
        let imageNode = ImageNode(range: nil, source: "", altText: nil, title: nil)
        let layout = LayoutResult(node: imageNode, size: CGSize(width: 100, height: 50))

        let view = AsyncImageView(frame: .zero)
        view.configure(with: layout)
        // URL(string: "") returns nil, so guard exits — should not crash
    }

    // MARK: - AsyncCodeView

    func testAsyncCodeViewHasSubviews() {
        let view = AsyncCodeView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        // Should have textView + copyButton as subviews
        XCTAssertEqual(view.subviews.count, 2)
    }

    func testAsyncCodeViewLayoutSubviews() {
        let view = AsyncCodeView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        view.layoutSubviews()

        // TextView should be inset by padding (16)
        let textView = view.subviews.first(where: { $0 is AsyncTextView })
        XCTAssertNotNil(textView)
        XCTAssertEqual(textView?.frame.origin.x, 16)
        XCTAssertEqual(textView?.frame.origin.y, 16)
    }

    // MARK: - AsyncTextView

    func testAsyncTextViewConfigureWithNilString() {
        let node = TextNode(range: nil, text: "")
        let layout = LayoutResult(node: node, size: CGSize(width: 200, height: 50), attributedString: nil)

        let view = AsyncTextView(frame: .zero)
        view.configure(with: layout)

        // Should clear layer contents and not crash
        XCTAssertNil(view.layer.contents)
    }

    // MARK: - MarkdownCollectionViewCell Routing

    func testCellRoutesImageNodeToAsyncImageView() {
        let imageNode = ImageNode(range: nil, source: "https://example.com/img.png", altText: "alt", title: nil)
        let imageLayout = LayoutResult(node: imageNode, size: CGSize(width: 320, height: 200))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: imageLayout)

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncImageView)
    }

    func testCellRoutesCodeBlockToAsyncCodeView() {
        let codeNode = CodeBlockNode(range: nil, language: "swift", code: "let x = 1")
        let layout = LayoutResult(node: codeNode, size: CGSize(width: 320, height: 100))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncCodeView)
    }

    func testCellRoutesDefaultNodeToAsyncTextView() {
        let textNode = ParagraphNode(range: nil, children: [])
        let layout = LayoutResult(node: textNode, size: CGSize(width: 320, height: 50))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncTextView)
    }

    func testCellReconfigurePurgesOldView() {
        let textNode = ParagraphNode(range: nil, children: [])
        let textLayout = LayoutResult(node: textNode, size: CGSize(width: 320, height: 50))

        let codeNode = CodeBlockNode(range: nil, language: nil, code: "x")
        let codeLayout = LayoutResult(node: codeNode, size: CGSize(width: 320, height: 100))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: textLayout)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncTextView)

        cell.configure(with: codeLayout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncCodeView)
    }

    func testCellPrepareForReuseRemovesAllSubviews() {
        let textNode = ParagraphNode(range: nil, children: [])
        let layout = LayoutResult(node: textNode, size: CGSize(width: 320, height: 50))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)

        cell.prepareForReuse()
        XCTAssertEqual(cell.contentView.subviews.count, 0)
    }
}
#endif
