import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class AsyncCodeViewCopyTests: XCTestCase {

    // MARK: - Helpers

    private func findCopyButton(in view: AsyncCodeView) -> UIButton? {
        view.subviews.compactMap { $0 as? UIButton }.first
    }

    /// In-memory stand-in for the system pasteboard so tests never touch
    /// `UIPasteboard.general`, which can block headlessly under XCTest.
    private final class CopySinkSpy {
        private(set) var copiedStrings: [String] = []
        private(set) var invocationCount = 0

        var handler: (String) -> Void {
            { [self] copied in
                invocationCount += 1
                copiedStrings.append(copied)
            }
        }

        var lastCopiedString: String? { copiedStrings.last }
    }

    private func configuredCodeView(code: String = "let x = 42", language: String? = "swift", copySink: CopySinkSpy? = nil) -> AsyncCodeView {
        let node = CodeBlockNode(range: nil, language: language, code: code)
        let attrStr = NSAttributedString(string: code)
        let layout = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 100),
            attributedString: attrStr
        )
        let view = AsyncCodeView(frame: CGRect(origin: .zero, size: layout.size))
        if let copySink {
            view.copySink = copySink.handler
        }
        view.configure(with: layout)
        return view
    }

    // MARK: - Tests

    func testCopyButtonExists() {
        let view = AsyncCodeView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let button = findCopyButton(in: view)
        XCTAssertNotNil(button, "AsyncCodeView should contain a UIButton for copying")
    }

    func testCopySetsClipboard() {
        let sink = CopySinkSpy()
        let view = configuredCodeView(code: "print(\"hello\")", copySink: sink)
        let button = findCopyButton(in: view)!

        button.sendActions(for: .touchUpInside)

        XCTAssertEqual(sink.lastCopiedString, "print(\"hello\")")
        XCTAssertEqual(sink.invocationCount, 1)
    }

    func testCopyWithEmptyCodeDoesNothing() {
        let sink = CopySinkSpy()
        let view = configuredCodeView(code: "", copySink: sink)
        let button = findCopyButton(in: view)!

        button.sendActions(for: .touchUpInside)

        // Copy sink should never be invoked since rawCode is empty
        XCTAssertEqual(sink.invocationCount, 0)
        XCTAssertNil(sink.lastCopiedString)
    }

    func testCopyButtonImageChangesAfterCopy() {
        let sink = CopySinkSpy()
        let view = configuredCodeView(copySink: sink)
        let button = findCopyButton(in: view)!

        let originalImage = button.image(for: .normal)
        XCTAssertNotNil(originalImage)

        button.sendActions(for: .touchUpInside)

        // After copy, icon should change to checkmark
        let newImage = button.image(for: .normal)
        XCTAssertNotNil(newImage)
        XCTAssertNotEqual(originalImage, newImage, "Button image should change after copy action")
    }

    func testCopyButtonImageRevertsAfterDelay() async throws {
        let sink = CopySinkSpy()
        let view = configuredCodeView(copySink: sink)
        let button = findCopyButton(in: view)!

        let originalImage = button.image(for: .normal)
        button.sendActions(for: .touchUpInside)

        // Wait for the 2-second revert animation
        try await Task.sleep(for: .seconds(2.5))

        let revertedImage = button.image(for: .normal)
        XCTAssertEqual(originalImage, revertedImage, "Button image should revert to original after delay")
    }

    func testPrepareForReuseRestoresCopyButtonImmediately() {
        let sink = CopySinkSpy()
        let view = configuredCodeView(copySink: sink)
        let button = findCopyButton(in: view)!
        let originalImage = button.image(for: .normal)

        button.sendActions(for: .touchUpInside)
        XCTAssertNotEqual(button.image(for: .normal), originalImage)

        view.prepareForReuse()

        XCTAssertEqual(button.image(for: .normal), originalImage)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(sink.invocationCount, 1, "prepareForReuse should clear the previous code payload")
    }

    func testCopyWithDiagramNode() {
        let sink = CopySinkSpy()
        let node = DiagramNode(range: nil, language: .mermaid, source: "graph TD; A-->B;")
        let attrStr = NSAttributedString(string: "graph TD; A-->B;")
        let layout = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 100),
            attributedString: attrStr
        )
        let view = AsyncCodeView(frame: CGRect(origin: .zero, size: layout.size))
        view.copySink = sink.handler
        view.configure(with: layout)
        let button = findCopyButton(in: view)!

        button.sendActions(for: .touchUpInside)

        XCTAssertEqual(sink.lastCopiedString, "graph TD; A-->B;")
        XCTAssertEqual(sink.invocationCount, 1)
    }
}
#endif
