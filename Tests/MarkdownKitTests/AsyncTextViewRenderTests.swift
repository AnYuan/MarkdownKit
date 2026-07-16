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

    func testConfigureRendersAttachmentBackedString() {
        let attachment = NSTextAttachment()
        attachment.image = makeAttachmentImage()
        attachment.bounds = CGRect(x: 0, y: 0, width: 48, height: 20)

        let layout = LayoutResult(
            node: TextNode(range: nil, text: "attachment"),
            size: CGSize(width: 80, height: 28),
            attributedString: NSAttributedString(attachment: attachment)
        )

        let view = AsyncTextView(frame: layout.size == .zero ? .zero : CGRect(origin: .zero, size: layout.size))
        view.displaysAsynchronously = false
        view.configure(with: layout)

        guard let contents = view.layer.contents else {
            XCTFail("Expected attachment rendering to produce a CGImage")
            return
        }

        // `CALayer.contents` is typed `Any?`. Swift 6 treats a conditional
        // downcast to a Core Foundation type (`contents as? CGImage`) as
        // always succeeding and rejects it as a redundant cast, so verify
        // the dynamic type explicitly via `CFGetTypeID` instead.
        guard CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
            XCTFail("Expected layer.contents to be a CGImage, got \(type(of: contents))")
            return
        }
        let cgImage = contents as! CGImage

        XCTAssertTrue(
            TestHelper.imageContainsVisibleNonWhitePixel(cgImage),
            "Attachment rendering should draw visible pixels into layer.contents"
        )
    }

    private func makeAttachmentImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 20))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 20))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(2)
            context.cgContext.stroke(CGRect(x: 1, y: 1, width: 46, height: 18))
        }
    }

}
#endif
