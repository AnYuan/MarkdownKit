import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class AsyncTextViewRenderTests: XCTestCase {

    // MARK: - Helpers

    private func waitForLayerContents(_ view: UIView, timeout: TimeInterval = 3.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while view.layer.contents == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Tests

    func testConfigureRendersToLayerContents() async throws {
        let layout = await TestHelper.solveLayout("Hello world", width: 300)
        guard let childLayout = layout.children.first else {
            XCTFail("Expected at least one child layout")
            return
        }

        let view = AsyncTextView(frame: CGRect(origin: .zero, size: childLayout.size))
        view.configure(with: childLayout)

        try await waitForLayerContents(view)
        XCTAssertNotNil(view.layer.contents, "renderImage() should produce a CGImage in layer.contents")
    }

    func testConfigureWithNilStringClearsContents() async throws {
        let node = TextNode(range: nil, text: "")
        let layout = LayoutResult(node: node, size: CGSize(width: 200, height: 50), attributedString: nil)

        let view = AsyncTextView(frame: .zero)
        view.configure(with: layout)

        // Nil path is synchronous — contents should be nil immediately
        XCTAssertNil(view.layer.contents)
    }

    func testConfigureWithEmptyStringClearsContents() async throws {
        let node = TextNode(range: nil, text: "")
        let emptyStr = NSAttributedString(string: "")
        let layout = LayoutResult(node: node, size: CGSize(width: 200, height: 50), attributedString: emptyStr)

        let view = AsyncTextView(frame: .zero)
        view.configure(with: layout)

        // Empty string (length == 0) path is synchronous
        XCTAssertNil(view.layer.contents)
    }

    func testReconfigureCancelsPreviousTask() async throws {
        let layoutA = await TestHelper.solveLayout("First paragraph with some text content.", width: 300)
        let layoutB = await TestHelper.solveLayout("Second different paragraph.", width: 300)

        guard let childA = layoutA.children.first, let childB = layoutB.children.first else {
            XCTFail("Expected child layouts")
            return
        }

        let view = AsyncTextView(frame: CGRect(origin: .zero, size: childB.size))

        // Configure with A, then immediately reconfigure with B
        view.configure(with: childA)
        view.configure(with: childB)

        try await waitForLayerContents(view)
        // The second task should complete without crash
        XCTAssertNotNil(view.layer.contents)
    }

    func testConfigureWithMultilineMarkdown() async throws {
        let markdown = """
        This is a paragraph with **bold** and *italic* formatting that spans
        multiple lines and should exercise the full rendering pipeline.
        """
        let layout = await TestHelper.solveLayout(markdown, width: 300)
        guard let childLayout = layout.children.first else {
            XCTFail("Expected at least one child layout")
            return
        }

        let view = AsyncTextView(frame: CGRect(origin: .zero, size: childLayout.size))
        view.configure(with: childLayout)

        try await waitForLayerContents(view)
        XCTAssertNotNil(view.layer.contents, "Multi-line styled text should render to layer.contents")
    }
}
#endif
