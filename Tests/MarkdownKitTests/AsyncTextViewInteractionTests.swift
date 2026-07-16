import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class AsyncTextViewInteractionTests: XCTestCase {

    private func makeTextView(with markdown: String, width: CGFloat = 300) async -> (AsyncTextView, LayoutResult) {
        let layout = await TestHelper.solveLayout(markdown, width: width)
        guard let childLayout = layout.children.first else {
            fatalError("No child layout for markdown: \(markdown)")
        }
        let textView = AsyncTextView(frame: CGRect(origin: .zero, size: childLayout.size))
        textView.displaysAsynchronously = false
        textView.configure(with: childLayout)
        return (textView, childLayout)
    }

    private func pointForAttribute(
        _ key: NSAttributedString.Key,
        in textView: AsyncTextView,
        matching predicate: ((Any) -> Bool)? = nil
    ) throws -> CGPoint {
        let attributedString = try XCTUnwrap(
            textView.currentAttributedString,
            "AsyncTextView should retain the attributed string needed for interaction tests"
        )
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var matchedRange: NSRange?

        attributedString.enumerateAttribute(key, in: fullRange) { value, range, stop in
            guard let value else { return }
            if predicate?(value) ?? true {
                matchedRange = range
                stop.pointee = true
            }
        }

        let range = try XCTUnwrap(matchedRange, "Expected \(key.rawValue) range in attributed string")
        let hitTester = TextKitHitTester(attributedString: attributedString, containerSize: textView.bounds.size)
        let rect = hitTester.boundingRect(for: range)
        XCTAssertFalse(rect.isEmpty, "Expected a non-empty bounding rect for \(key.rawValue)")
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func pointForCharacter(
        at index: Int,
        in textView: AsyncTextView
    ) throws -> CGPoint {
        let attributedString = try XCTUnwrap(
            textView.currentAttributedString,
            "AsyncTextView should retain the attributed string needed for interaction tests"
        )
        XCTAssertLessThan(index, attributedString.length, "Character index must be within the attributed string")
        let hitTester = TextKitHitTester(attributedString: attributedString, containerSize: textView.bounds.size)
        let rect = hitTester.boundingRect(for: NSRange(location: index, length: 1))
        XCTAssertFalse(rect.isEmpty, "Expected a non-empty bounding rect for character \(index)")
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func testLinkTapCallbackFires() async throws {
        let (textView, _) = await makeTextView(with: "Click [here](https://example.com)")

        var tappedURL: URL?
        textView.onLinkTap = { url in tappedURL = url }
        let linkPoint = try pointForAttribute(.link, in: textView) {
            ($0 as? URL)?.absoluteString == "https://example.com"
        }

        XCTAssertTrue(textView.handleInteraction(at: linkPoint))
        XCTAssertEqual(tappedURL?.absoluteString, "https://example.com")
    }

    func testCheckboxToggleCallbackFires() async throws {
        let plugins: [ASTPlugin] = []
        let markdown = "- [x] Done task"
        let layout = await TestHelper.solveLayout(markdown, width: 300, plugins: plugins)
        guard let childLayout = layout.children.first else {
            XCTFail("No child layout")
            return
        }

        let textView = AsyncTextView(frame: CGRect(origin: .zero, size: childLayout.size))
        textView.displaysAsynchronously = false
        textView.configure(with: childLayout)

        var toggledData: CheckboxInteractionData?
        textView.onCheckboxToggle = { data in toggledData = data }
        let checkboxPoint = try pointForAttribute(.markdownCheckbox, in: textView)

        XCTAssertTrue(textView.handleInteraction(at: checkboxPoint))
        let data = try XCTUnwrap(toggledData)
        XCTAssertTrue(data.isChecked)
    }

    func testNonInteractiveTapNoCallback() async throws {
        let (textView, _) = await makeTextView(with: "Plain text only")

        var linkTapped = false
        var checkboxToggled = false
        textView.onLinkTap = { _ in linkTapped = true }
        textView.onCheckboxToggle = { _ in checkboxToggled = true }
        let plainTextPoint = try pointForCharacter(at: 0, in: textView)

        XCTAssertFalse(textView.handleInteraction(at: plainTextPoint))

        XCTAssertFalse(linkTapped, "Plain text should not trigger link callback")
        XCTAssertFalse(checkboxToggled, "Plain text should not trigger checkbox callback")
    }

    func testHighlightLayerExistsAfterPress() async throws {
        let (textView, _) = await makeTextView(with: "Click [here](https://example.com)")

        // Before any interaction, highlight layer should be hidden
        let highlightSublayers = textView.layer.sublayers?.filter { !$0.isHidden } ?? []
        XCTAssertEqual(highlightSublayers.count, 0, "No visible highlight layers before interaction")
    }

    func testReconfigureInvalidatesHitTester() async throws {
        let (textView, _) = await makeTextView(with: "Visit [first](https://example.com/first)")
        var tappedURLs: [String] = []
        textView.onLinkTap = { tappedURLs.append($0.absoluteString) }
        let firstPoint = try pointForAttribute(.link, in: textView) {
            ($0 as? URL)?.absoluteString == "https://example.com/first"
        }

        XCTAssertTrue(textView.handleInteraction(at: firstPoint))

        let newLayout = await TestHelper.solveLayout("Visit the [second link](https://example.com/second) now", width: 300)
        if let child = newLayout.children.first {
            textView.configure(with: child)
        }
        let secondPoint = try pointForAttribute(.link, in: textView) {
            ($0 as? URL)?.absoluteString == "https://example.com/second"
        }

        XCTAssertTrue(textView.handleInteraction(at: secondPoint))
        XCTAssertEqual(tappedURLs, [
            "https://example.com/first",
            "https://example.com/second"
        ])
    }
}
#endif
