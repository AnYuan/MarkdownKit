import XCTest
import SnapshotTesting
import Markdown
@testable import MarkdownKit

#if os(macOS)
import AppKit

@MainActor
final class SnapshotTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    func testTableRendering() async throws {
        let markdown = """
        | Header 1 | Header 2 |
        | :--- | ---: |
        | Row 1 left | Row 1 right |
        | Row 2 left | Row 2 right |
        """
        
        let parser = MarkdownParser()
        let document = parser.parse(markdown)
        
        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: document, constrainedToWidth: 400)
        guard let layout = layoutRoot.children.first else {
            XCTFail("No child layout generated")
            return
        }
        
        // Ensure size is non-zero
        XCTAssertGreaterThan(layout.size.width, 0)
        XCTAssertGreaterThan(layout.size.height, 0)
        
        let item = MarkdownItemView()
        item.loadView()
        item.view.frame = NSRect(origin: .zero, size: layout.size)
        item.configure(with: layout)
        
        let container = NSView(frame: NSRect(origin: .zero, size: layout.size))
        container.addSubview(item.view)
        
        // Assert snapshot directly on the container view
        assertSnapshot(of: container, as: .image)
    }
    
    func testCodeBlockRendering() async throws {
        let markdown = """
        ```swift
        func hello() {
            print("World")
        }
        ```
        """
        
        let parser = MarkdownParser()
        let document = parser.parse(markdown)
        
        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: document, constrainedToWidth: 400)
        guard let layout = layoutRoot.children.first else {
            XCTFail("No child layout generated")
            return
        }
        
        // Ensure size is non-zero
        XCTAssertGreaterThan(layout.size.width, 0)
        XCTAssertGreaterThan(layout.size.height, 0)
        
        let item = MarkdownItemView()
        item.loadView()
        item.view.frame = NSRect(origin: .zero, size: layout.size)
        item.configure(with: layout)
        
        let container = NSView(frame: NSRect(origin: .zero, size: layout.size))
        container.addSubview(item.view)
        
        // Assert snapshot directly on the container view
        assertSnapshot(of: container, as: .image)
    }
}
#endif
