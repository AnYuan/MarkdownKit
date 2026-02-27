import XCTest
@testable import MyMarkdown

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class TextKitCalculatorTests: XCTestCase {

    func testEmptyStringReturnsZeroSize() {
        let calc = TextKitCalculator()
        let empty = NSAttributedString(string: "")
        let size = calc.calculateSize(for: empty, constrainedToWidth: 400)
        XCTAssertEqual(size, .zero)
    }

    func testSingleLineTextFitsWithinWidth() {
        let calc = TextKitCalculator()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Font.systemFont(ofSize: 16)
        ]
        let str = NSAttributedString(string: "Hello", attributes: attrs)
        let size = calc.calculateSize(for: str, constrainedToWidth: 400)

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThanOrEqual(size.width, 400)
    }

    func testLongTextWrapsAndIncreasesHeight() {
        let calc = TextKitCalculator()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Font.systemFont(ofSize: 16)
        ]
        let longText = String(repeating: "Word ", count: 200)
        let str = NSAttributedString(string: longText, attributes: attrs)

        let narrowSize = calc.calculateSize(for: str, constrainedToWidth: 100)
        let wideSize = calc.calculateSize(for: str, constrainedToWidth: 800)

        // Narrow constraint should produce taller layout
        XCTAssertGreaterThan(narrowSize.height, wideSize.height)
        // Both should respect width constraint
        XCTAssertLessThanOrEqual(narrowSize.width, 100)
        XCTAssertLessThanOrEqual(wideSize.width, 800)
    }

    func testDifferentFontSizesProduceDifferentHeights() {
        let calc = TextKitCalculator()
        let text = "Sample text"

        let smallStr = NSAttributedString(string: text, attributes: [
            .font: Font.systemFont(ofSize: 12)
        ])
        let largeStr = NSAttributedString(string: text, attributes: [
            .font: Font.systemFont(ofSize: 32)
        ])

        let smallSize = calc.calculateSize(for: smallStr, constrainedToWidth: 400)
        let largeSize = calc.calculateSize(for: largeStr, constrainedToWidth: 400)

        XCTAssertGreaterThan(largeSize.height, smallSize.height)
    }
}
