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
    
    func testMathRendering() async throws {
        let markdown = """
        Block math:
        
        $$
        e^{i\\pi} + 1 = 0
        $$
        
        Inline math: $E=mc^2$
        """
        
        let parser = MarkdownParser()
        let document = parser.parse(markdown)
        
        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: document, constrainedToWidth: 400)
        
        // Assert snapshot for the entire document wrapper container 
        let totalHeight = layoutRoot.children.reduce(0) { $0 + $1.size.height }
        let container = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 400, height: totalHeight)))
        
        // Let's just stack the children
        var currentY: CGFloat = totalHeight
        for childLayout in layoutRoot.children {
            let item = MarkdownItemView()
            item.loadView()
            item.view.frame = NSRect(x: 0, y: currentY - childLayout.size.height, width: childLayout.size.width, height: childLayout.size.height)
            item.configure(with: childLayout)
            currentY -= childLayout.size.height
            container.addSubview(item.view)
        }
        
        assertSnapshot(of: container, as: .image)
    }
    
    func testTasklistRendering() async throws {
        let markdown = """
        - [ ] Unfinished Task
        - [x] Finished Task
        - Standard Bullet
        """
        
        let parser = MarkdownParser()
        let document = parser.parse(markdown)
        
        let solver = LayoutSolver()
        let layoutRoot = await solver.solve(node: document, constrainedToWidth: 400)
        
        guard let layout = layoutRoot.children.first else {
            XCTFail()
            return
        }
        
        let item = MarkdownItemView()
        item.loadView()
        item.view.frame = NSRect(origin: .zero, size: layout.size)
        item.configure(with: layout)
        
        let container = NSView(frame: NSRect(origin: .zero, size: layout.size))
        container.addSubview(item.view)
        
        assertSnapshot(of: container, as: .image)
    }
}
#endif
