import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

final class TextKitHitTesterTests: XCTestCase {

    private func makeTester(
        string: String = "Hello world",
        attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16)],
        width: CGFloat = 200
    ) -> (TextKitHitTester, NSAttributedString) {
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let tester = TextKitHitTester(attributedString: attrString, containerSize: CGSize(width: width, height: 1000))
        return (tester, attrString)
    }

    func testCharacterIndexAtKnownPosition() {
        let (tester, _) = makeTester()
        // The center of the text area should return a valid character index
        let index = tester.characterIndex(at: CGPoint(x: 10, y: 10))
        XCTAssertNotNil(index, "Should find a character near top-left of text")
    }

    func testCharacterIndexOutsideBoundsReturnsNil() {
        let (tester, _) = makeTester()
        let index = tester.characterIndex(at: CGPoint(x: -100, y: -100))
        XCTAssertNil(index, "Should return nil for points far outside text bounds")
    }

    func testLinkAttributeResolution() {
        let url = URL(string: "https://example.com")!
        let attrString = NSMutableAttributedString(string: "Click here", attributes: [
            .font: UIFont.systemFont(ofSize: 16)
        ])
        attrString.addAttribute(.link, value: url, range: NSRange(location: 6, length: 4)) // "here"

        let tester = TextKitHitTester(
            attributedString: attrString,
            containerSize: CGSize(width: 200, height: 100)
        )

        // Index 7 is within "here" (the link)
        let resolved: URL? = tester.attribute(.link, at: 7)
        XCTAssertEqual(resolved, url, "Should resolve the link URL at the attributed range")
    }

    func testCheckboxAttributeResolution() {
        let data = CheckboxInteractionData(
            isChecked: true,
            range: SourceRange(
                start: SourceLocation(line: 1, column: 1, source: nil),
                end: SourceLocation(line: 1, column: 10, source: nil)
            )
        )
        let attrString = NSMutableAttributedString(string: "☑ Task", attributes: [
            .font: UIFont.systemFont(ofSize: 16)
        ])
        attrString.addAttribute(.markdownCheckbox, value: data, range: NSRange(location: 0, length: 2))

        let tester = TextKitHitTester(
            attributedString: attrString,
            containerSize: CGSize(width: 200, height: 100)
        )

        let resolved: CheckboxInteractionData? = tester.attribute(.markdownCheckbox, at: 0)
        XCTAssertNotNil(resolved, "Should resolve checkbox data at the attributed range")
        XCTAssertTrue(resolved?.isChecked ?? false)
    }

    func testBoundingRectNonEmpty() {
        let (tester, attrString) = makeTester()
        let range = NSRange(location: 0, length: attrString.length)
        let rect = tester.boundingRect(for: range)
        XCTAssertGreaterThan(rect.width, 0, "Bounding rect should have positive width")
        XCTAssertGreaterThan(rect.height, 0, "Bounding rect should have positive height")
    }

    func testEffectiveRangeSpansFullAttribute() {
        let attrString = NSMutableAttributedString(string: "Click here now", attributes: [
            .font: UIFont.systemFont(ofSize: 16)
        ])
        let linkRange = NSRange(location: 6, length: 4) // "here"
        attrString.addAttribute(.link, value: URL(string: "https://example.com")!, range: linkRange)

        let tester = TextKitHitTester(
            attributedString: attrString,
            containerSize: CGSize(width: 200, height: 100)
        )

        let effective = tester.effectiveRange(of: .link, at: 7) // middle of "here"
        XCTAssertEqual(effective, linkRange, "Effective range should span the full link attribute")
    }
}
#endif
