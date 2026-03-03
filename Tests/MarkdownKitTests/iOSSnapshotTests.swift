import XCTest
import SnapshotTesting
@testable import MarkdownKit

#if os(iOS)
import UIKit

@MainActor
final class iOSSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private func snapshotView(for layout: LayoutResult) async throws -> UIView {
        let view: UIView
        switch layout.node {
        case is CodeBlockNode, is DiagramNode:
            let codeView = AsyncCodeView(frame: CGRect(origin: .zero, size: layout.size))
            codeView.configure(with: layout)
            view = codeView
        default:
            let textView = AsyncTextView(frame: CGRect(origin: .zero, size: layout.size))
            textView.configure(with: layout)
            view = textView
        }
        try await waitForLayerContents(view)
        return view
    }

    private func waitForLayerContents(_ view: UIView, timeout: TimeInterval = 3.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        // For code views, check the inner text view's layer
        let targetLayer: CALayer
        if let codeView = view as? AsyncCodeView,
           let textView = codeView.subviews.first(where: { $0 is AsyncTextView }) {
            targetLayer = textView.layer
        } else {
            targetLayer = view.layer
        }
        while targetLayer.contents == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Snapshot Tests

    func testParagraphSnapshot() async throws {
        let markdown = "Hello, **bold** and *italic* text."
        let layout = await TestHelper.solveLayout(markdown, width: 320)
        guard let child = layout.children.first else {
            XCTFail("Expected paragraph layout")
            return
        }

        let view = try await snapshotView(for: child)
        assertSnapshot(of: view, as: .image(size: child.size))
    }

    func testCodeBlockSnapshot() async throws {
        let markdown = """
        ```swift
        func hello() {
            print("World")
        }
        ```
        """
        let layout = await TestHelper.solveLayout(markdown, width: 320)
        guard let child = layout.children.first else {
            XCTFail("Expected code block layout")
            return
        }

        let view = try await snapshotView(for: child)
        assertSnapshot(of: view, as: .image(size: child.size))
    }

    func testTableSnapshot() async throws {
        let markdown = """
        | Header 1 | Header 2 |
        | :--- | ---: |
        | Row 1 left | Row 1 right |
        | Row 2 left | Row 2 right |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 375)
        guard let child = layout.children.first else {
            XCTFail("Expected table layout")
            return
        }

        let view = try await snapshotView(for: child)
        assertSnapshot(of: view, as: .image(size: child.size))
    }

    func testTaskListSnapshot() async throws {
        let markdown = """
        - [ ] Unfinished Task
        - [x] Finished Task
        - Standard Bullet
        """
        let layout = await TestHelper.solveLayout(markdown, width: 320)
        guard let child = layout.children.first else {
            XCTFail("Expected list layout")
            return
        }

        let view = try await snapshotView(for: child)
        assertSnapshot(of: view, as: .image(size: child.size))
    }

    func testBlockQuoteSnapshot() async throws {
        let markdown = "> This is a quoted block of text."
        let layout = await TestHelper.solveLayout(markdown, width: 320)
        guard let child = layout.children.first else {
            XCTFail("Expected blockquote layout")
            return
        }

        let view = try await snapshotView(for: child)
        assertSnapshot(of: view, as: .image(size: child.size))
    }

    func testHeadingSnapshot() async throws {
        let markdown = "# Heading Level 1"
        let layout = await TestHelper.solveLayout(markdown, width: 320)
        guard let child = layout.children.first else {
            XCTFail("Expected heading layout")
            return
        }

        let view = try await snapshotView(for: child)
        assertSnapshot(of: view, as: .image(size: child.size))
    }
}
#endif
