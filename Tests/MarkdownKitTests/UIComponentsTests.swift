import XCTest
@testable import MarkdownKit

// We can only test UIKit components on platforms that support it
#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class UIComponentsTests: XCTestCase {
    
    func testCellRecyclingPreservesSameTypeHostedView() async throws {
        // 1. Setup Mock AST with two paragraphs (same node type).
        let parser = MarkdownParser()
        let docNodes = parser.parse("""
        First paragraph.

        Second paragraph.
        """)

        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: docNodes, constrainedToWidth: 320)
        let firstLayout = layoutRoot.children[0]
        let secondLayout = layoutRoot.children[1]

        // 2. First configure attaches an AsyncTextView.
        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: firstLayout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        guard let firstHostedView = cell.contentView.subviews.first as? AsyncTextView else {
            XCTFail("Expected AsyncTextView after first configure")
            return
        }

        // 3. prepareForReuse must keep the hosted view alive (state reset only).
        // This is the heart of Texture-style cell pooling: defeating it forces a
        // fresh AsyncTextView allocation on every visible scroll row.
        cell.prepareForReuse()
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertIdentical(cell.contentView.subviews.first, firstHostedView)
        XCTAssertNil(firstHostedView.currentAttributedString)

        // 4. Re-configure with the same node type → reuses the same view instance.
        cell.configure(with: secondLayout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertIdentical(cell.contentView.subviews.first, firstHostedView)
        XCTAssertNotNil(firstHostedView.currentAttributedString)
    }

    func testCellRecyclingReplacesHostedViewOnTypeChange() async throws {
        // 1. Setup Mock AST with mixed node types.
        let parser = MarkdownParser()
        let docNodes = parser.parse("""
        # Heading

        ```swift
        print("Code")
        ```
        """)

        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: docNodes, constrainedToWidth: 320)
        let headerLayout = layoutRoot.children[0]
        let codeLayout = layoutRoot.children[1]

        // 2. First configure attaches an AsyncTextView for the header.
        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: headerLayout)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncTextView)

        // 3. Re-configure with a CodeBlock → swap to AsyncCodeView.
        cell.prepareForReuse()
        cell.configure(with: codeLayout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncCodeView)
    }
}
#endif
