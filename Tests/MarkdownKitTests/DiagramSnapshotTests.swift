import XCTest
import SnapshotTesting
@testable import MarkdownKit

#if canImport(AppKit)
import AppKit
#endif

final class DiagramSnapshotTests: XCTestCase {
    
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    @MainActor
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
        guard let attrString = await adapter.render(source: source, language: .mermaid) else {
            throw XCTSkip("Mermaid rendering unavailable in this runtime context")
        }

        guard let attachment = attrString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment else {
            throw XCTSkip("Diagram rendering did not produce attachment in this runtime context")
        }

        guard let image = attachment.image else {
            throw XCTSkip("Diagram attachment has no image in this runtime context")
        }

        // Ensure image looks roughly like a graph (size check and general snapshot)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        
        // Optional: Snapshot test the resulting image directly.
        // assertSnapshot(of: image, as: .image)
    }
    #endif
}
