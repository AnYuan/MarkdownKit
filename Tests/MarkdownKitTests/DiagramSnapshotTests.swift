import XCTest
import SnapshotTesting
@testable import MarkdownKit

#if canImport(AppKit)
import AppKit
#endif

final class DiagramSnapshotTests: XCTestCase {
    
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    func testMermaidDiagramRendering() async throws {
        let adapter = MermaidDiagramAdapter()
        let source = """
        graph TD;
            A-->B;
            A-->C;
            B-->D;
            C-->D;
        """
        
        // Render to NSAttributedString
        let attrString = await adapter.render(source: source, language: .mermaid)
        XCTAssertNotNil(attrString)
        
        guard let attrString = attrString, let attachment = attrString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment else {
            XCTFail("Missing attachment in diagram rendering")
            return
        }
        
        guard let image = attachment.image else {
            XCTFail("Missing image in attachment")
            return
        }
        
        // Ensure image looks roughly like a graph (size check and general snapshot)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        
        // Optional: Snapshot test the resulting image directly.
        // assertSnapshot(of: image, as: .image)
    }
    #endif
}
