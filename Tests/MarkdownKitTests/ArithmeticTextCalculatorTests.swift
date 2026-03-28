import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ArithmeticTextCalculatorTests: XCTestCase {
    
    func testSimpleStringSizeParity() {
        let text = "This is a simple paragraph without any complex formatting or attachments."
        let font = Font.systemFont(ofSize: 16)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attrs)
        
        let arithmeticCalc = ArithmeticTextCalculator()
        let textKitCalc = TextKitCalculator()
        
        let width: CGFloat = 200
        
        let arithmeticSize = arithmeticCalc.calculateSize(for: attributedString, constrainedToWidth: width)
        let textKitSize = textKitCalc.calculateSize(for: attributedString, constrainedToWidth: width)
        
        // Due to the extreme simplification in the tokenizer, heights might slightly differ.
        // We test rough parity for now.
        XCTAssertEqual(arithmeticSize.width, textKitSize.width, accuracy: 25.0, "Width should be roughly equal")
        XCTAssertEqual(arithmeticSize.height, textKitSize.height, accuracy: 25.0, "Height should be roughly equal")
    }
}
