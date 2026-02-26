import XCTest
@testable import MyMarkdown

// We can only test UIKit components on platforms that support it
#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class UIComponentsTests: XCTestCase {
    
    func testVirtualizationPurging() async throws {
        // 1. Setup Mock AST
        let parser = MarkdownParser()
        let docNodes = parser.parse("""
        # Welcome
        This is text.
        ```swift
        print("Code")
        ```
        """)
        
        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: docNodes, constrainedToWidth: 320)
        
        // 2. Extrapolate individual blocks
        let headerLayout = layoutRoot.children[0]
        let paragraphLayout = layoutRoot.children[1]
        let codeLayout = layoutRoot.children[2]
        
        // 3. Test View Mounting
        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: headerLayout)
        
        // Verify AsyncTextView was added
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncTextView)
        
        // 4. Test Cell Recycling (Crucial Texture feature)
        // When a cell is recycled, it must aggressively clear its subviews 
        // to free up memory before being configured with a new LayoutResult.
        cell.prepareForReuse()
        XCTAssertEqual(cell.contentView.subviews.count, 0)
        
        // 5. Re-configure with a different node type
        cell.configure(with: codeLayout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncCodeView)
    }
}
#endif
