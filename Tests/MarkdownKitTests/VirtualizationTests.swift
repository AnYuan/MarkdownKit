import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class VirtualizationTests: XCTestCase {

    func testLargeDocumentMemoryVirtualization() throws {
        // Construct a Markdown string with 500 paragraphs for speedy test execution
        let paragraphCount = 500
        var massiveMarkdown = ""
        for i in 1...paragraphCount {
            massiveMarkdown += "This is test paragraph \(i) to ensure memory virtualization remains stable under heavy load.\n\n"
        }

        let parser = MarkdownParser()
        var docNode: DocumentNode!

        // 1. Parsing Phase Performance/Memory
        PerformanceProfiler.measure(.astParsing) {
            docNode = parser.parse(massiveMarkdown)
        }

        XCTAssertEqual(docNode.children.count, paragraphCount)

        // 2. Layout Generation Phase
        let calculator = TextKitCalculator()
        let theme = Theme.default
        var layoutModels: [LayoutResult] = []
        
        PerformanceProfiler.measure(.layoutCalculation) {
            for child in docNode.children {
                if let paragraph = child as? ParagraphNode, let textNode = paragraph.children.first as? TextNode {
                    let str = NSAttributedString(string: textNode.text, attributes: [.font: theme.paragraph.font])
                    let size = calculator.calculateSize(for: str, constrainedToWidth: 400)
                    let layoutResult = LayoutResult(node: child, size: size, attributedString: str)
                    layoutModels.append(layoutResult)
                }
            }
        }
        
        XCTAssertEqual(layoutModels.count, paragraphCount)
        XCTAssertGreaterThan(layoutModels[0].size.height, 0)
    }
}
