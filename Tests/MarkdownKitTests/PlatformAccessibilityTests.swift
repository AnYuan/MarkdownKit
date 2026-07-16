import XCTest
@testable import MarkdownKit

final class PlatformAccessibilityTests: XCTestCase {

    func testAccessibilityLabelExtraction() {
        // Details Node
        let summaryText = TextNode(range: nil, text: "Secret Content")
        let summary = SummaryNode(range: nil, children: [summaryText])
        let details = DetailsNode(range: nil, isOpen: false, summary: summary, children: [])
        
        let layout1 = LayoutResult(node: details, size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityLabel(for: layout1), "Collapsible Section: Secret Content")
        
        // Math Node
        let math = MathNode(range: nil, style: .inline, equation: "E=mc^2")
        let layout2 = LayoutResult(node: math, size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityLabel(for: layout2), "Math Equation: E=mc^2")
        
        // Image Node
        let image = ImageNode(range: nil, source: "image.png", altText: "An image alt", title: nil)
        let layout3 = LayoutResult(node: image, size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityLabel(for: layout3), "Image: An image alt")
        
        // Generic Text Fallback
        let attrString = NSAttributedString(string: "Standard Text")
        let layout4 = LayoutResult(node: TextNode(range: nil, text: "Original"), size: .zero, attributedString: attrString)
        XCTAssertEqual(PlatformAccessibility.accessibilityLabel(for: layout4), "Standard Text")
    }

    func testAccessibilityValueExtraction() {
        // Details Expanded
        let detailsExpanded = DetailsNode(range: nil, isOpen: true, summary: nil, children: [])
        let layout1 = LayoutResult(node: detailsExpanded, size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityValue(for: layout1), "Expanded")
        
        // Details Collapsed
        let detailsCollapsed = DetailsNode(range: nil, isOpen: false, summary: nil, children: [])
        let layout2 = LayoutResult(node: detailsCollapsed, size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityValue(for: layout2), "Collapsed")
        
        // Checkbox Node
        let listItem = ListItemNode(range: nil, checkbox: .checked, children: [])
        let layout3 = LayoutResult(node: listItem, size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityValue(for: layout3), "Checked")
        
        // Checkbox Attributed String Fallback
        // Checkbox Attributed String Fallback (Creating an empty SourceRange dummy via parsing)
        let parser = MarkdownParser()
        let dummyDoc = parser.parse("[]")
        let dummyRange = dummyDoc.range!
        let attrStr = NSMutableAttributedString(string: "Task")
        attrStr.addAttribute(.markdownCheckbox, value: CheckboxInteractionData(isChecked: false, range: dummyRange), range: NSRange(location: 0, length: 4))
        let layout4 = LayoutResult(node: ParagraphNode(range: nil, children: []), size: .zero, attributedString: attrStr)
        XCTAssertEqual(PlatformAccessibility.accessibilityValue(for: layout4), "Unchecked")
    }

    func testAccessibilityHintExtraction() {
        let layoutDetails = LayoutResult(node: DetailsNode(range: nil, isOpen: false, summary: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityHint(for: layoutDetails), "Double-tap to expand or collapse")
        
        let layoutLink = LayoutResult(node: LinkNode(range: nil, destination: "", title: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityHint(for: layoutLink), "Double-tap to open link")
        
        let layoutEmpty = LayoutResult(node: ParagraphNode(range: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertNil(PlatformAccessibility.accessibilityHint(for: layoutEmpty))
    }

    #if canImport(UIKit)
    func testUIKitAccessibilityTraits() {
        let layoutDetails = LayoutResult(node: DetailsNode(range: nil, isOpen: false, summary: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertTrue(PlatformAccessibility.accessibilityTraits(for: layoutDetails).contains(.button))
        
        let layoutImage = LayoutResult(node: ImageNode(range: nil, source: "", altText: nil, title: nil), size: .zero, attributedString: nil)
        XCTAssertTrue(PlatformAccessibility.accessibilityTraits(for: layoutImage).contains(.image))
        
        let layoutGeneral = LayoutResult(node: ParagraphNode(range: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityTraits(for: layoutGeneral), .staticText)
    }
    #endif

    #if canImport(AppKit)
    func testAppKitAccessibilityRole() {
        let layoutDetails = LayoutResult(node: DetailsNode(range: nil, isOpen: false, summary: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityRole(for: layoutDetails), .button)
        
        let layoutCode = LayoutResult(node: CodeBlockNode(range: nil, language: nil, code: ""), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityRole(for: layoutCode), .group)
        
        let layoutTable = LayoutResult(node: TableNode(range: nil, columnAlignments: [], children: []), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityRole(for: layoutTable), .group)
        
        let layoutGeneral = LayoutResult(node: ParagraphNode(range: nil, children: []), size: .zero, attributedString: nil)
        XCTAssertEqual(PlatformAccessibility.accessibilityRole(for: layoutGeneral), .staticText)
    }
    #endif
}
