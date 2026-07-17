import XCTest
@testable import MarkdownKit

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

@MainActor
final class MacOSUIComponentsTests: XCTestCase {

    // MARK: - MarkdownItemView

    func testLoadViewCreatesNSView() {
        let item = MarkdownItemView()
        item.loadView()
        XCTAssertNotNil(item.view)
        XCTAssertTrue(item.view.wantsLayer, "View should have wantsLayer set to true")
    }

    func testConfigureAddsTextViewSubview() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Hello")])
        let attrStr = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 20),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 1, "Configure should add exactly one subview")
        XCTAssertTrue(item.view.subviews[0] is NSTextView, "Subview should be NSTextView")
    }

    func testConfigureWithCodeBlockSetsBackgroundAndCornerRadius() {
        let item = MarkdownItemView()
        item.loadView()

        let node = CodeBlockNode(range: nil, language: "swift", code: "let x = 1")
        let attrStr = NSAttributedString(string: "let x = 1", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 40),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        XCTAssertEqual(item.view.subviews.count, 1)

        guard let textView = item.view.subviews[0] as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }

        XCTAssertTrue(textView.drawsBackground, "Code block text view should draw background")
        XCTAssertTrue(textView.wantsLayer, "Code block text view should be layer-backed")
        XCTAssertEqual(textView.layer?.cornerRadius, 6, "Code block should have corner radius of 6")
    }

    func testConfigureUsesPrecomputedAccessibilityMetadata() {
        let item = MarkdownItemView()
        item.loadView()

        let layout = LayoutResult(
            node: ParagraphNode(range: nil, children: []),
            size: CGSize(width: 300, height: 20),
            attributedString: NSAttributedString(string: "Rendered text"),
            accessibility: AccessibilityMetadata(
                label: "Cached label",
                value: "Cached value",
                hint: "Cached help",
                nodeRoleHint: .table
            )
        )

        item.configure(with: layout)

        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertTrue(textView.isAccessibilityElement())
        XCTAssertEqual(textView.accessibilityRole(), .group)
        XCTAssertEqual(textView.accessibilityLabel(), "Cached label")
        XCTAssertEqual(textView.accessibilityValue(), "Cached value")
        XCTAssertEqual(textView.accessibilityHelp(), "Cached help")
    }

    func testConfigureExposesCheckedAndUncheckedCheckboxValues() {
        let item = MarkdownItemView()
        item.loadView()

        let checkedLayout = LayoutResult(
            node: ListItemNode(range: nil, checkbox: .checked, children: []),
            size: CGSize(width: 300, height: 20),
            attributedString: NSAttributedString(string: "Checked task")
        )
        let uncheckedLayout = LayoutResult(
            node: ListItemNode(range: nil, checkbox: .unchecked, children: []),
            size: CGSize(width: 300, height: 20),
            attributedString: NSAttributedString(string: "Unchecked task")
        )

        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }

        item.configure(with: checkedLayout)
        XCTAssertEqual(textView.accessibilityRole(), .checkBox)
        XCTAssertEqual((textView as NSView).accessibilityValue() as? NSNumber, NSNumber(value: 1))

        item.configure(with: uncheckedLayout)
        XCTAssertEqual(textView.accessibilityRole(), .checkBox)
        XCTAssertEqual((textView as NSView).accessibilityValue() as? NSNumber, NSNumber(value: 0))
    }

    func testConfigureWithNilAttributedStringLeavesViewEmpty() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 0),
            attributedString: nil
        )

        item.configure(with: layoutResult)
        
        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertEqual(textView.textStorage?.length ?? 0, 0, "Nil string should leave text view empty")
    }

    func testConfigureWithEmptyAttributedStringLeavesViewEmpty() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [])
        let attrStr = NSAttributedString(string: "")
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 0),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertEqual(textView.textStorage?.length ?? 0, 0, "Empty string should leave text view empty")
    }

    func testPrepareForReuseClearsHostedView() {
        let item = MarkdownItemView()
        item.loadView()

        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Hello")])
        let attrStr = NSAttributedString(string: "Hello", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 20),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)
        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertEqual(textView.textStorage?.string, "Hello")

        item.prepareForReuse()
        XCTAssertEqual(textView.textStorage?.length ?? 0, 0,
            "prepareForReuse should clear all text content from the recycled view")
    }

    func testDirectReconfigurationClearsAccessibilityAndStylingForEmptyLayout() {
        let item = MarkdownItemView()
        item.loadView()
        item.preferredContainerWidth = 420

        let configuredLayout = LayoutResult(
            node: CodeBlockNode(range: nil, language: nil, code: "code"),
            size: CGSize(width: 300, height: 40),
            attributedString: NSAttributedString(string: "code"),
            accessibility: AccessibilityMetadata(
                label: "Cached code",
                value: "Cached value",
                hint: "Cached help",
                nodeRoleHint: .codeBlock
            )
        )
        let emptyLayout = LayoutResult(
            node: ParagraphNode(range: nil, children: []),
            size: .zero,
            attributedString: nil
        )

        item.configure(with: configuredLayout)
        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertTrue(textView.wantsLayer)

        item.configure(with: emptyLayout)

        XCTAssertEqual(textView.textStorage?.length, 0)
        XCTAssertFalse(textView.isAccessibilityElement())
        XCTAssertEqual(textView.accessibilityRole(), .none)
        XCTAssertNil(textView.accessibilityLabel())
        XCTAssertNil(textView.accessibilityValue())
        XCTAssertNil(textView.accessibilityHelp())
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertEqual(textView.layer?.cornerRadius ?? 0, 0)
        XCTAssertEqual(textView.textContainerInset, .zero)
        XCTAssertFalse(textView.wantsLayer)
        XCTAssertEqual(item.preferredContainerWidth, 420)
    }

    func testPrepareForReuseClearsAccessibilityAndPreferredWidth() {
        let item = MarkdownItemView()
        item.loadView()
        item.preferredContainerWidth = 420

        let layout = LayoutResult(
            node: ParagraphNode(range: nil, children: []),
            size: CGSize(width: 300, height: 20),
            attributedString: NSAttributedString(string: "Accessible"),
            accessibility: AccessibilityMetadata(
                label: "Cached label",
                value: "Cached value",
                hint: "Cached help",
                nodeRoleHint: .details
            )
        )

        item.configure(with: layout)
        item.prepareForReuse()

        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertFalse(textView.isAccessibilityElement())
        XCTAssertEqual(textView.accessibilityRole(), .none)
        XCTAssertNil(textView.accessibilityLabel())
        XCTAssertNil(textView.accessibilityValue())
        XCTAssertNil(textView.accessibilityHelp())
        XCTAssertNil(item.preferredContainerWidth)
    }

    func testDirectReconfigurationClearsPreviousAccessibilityValues() {
        let item = MarkdownItemView()
        item.loadView()

        let firstLayout = LayoutResult(
            node: CodeBlockNode(range: nil, language: nil, code: "First"),
            size: CGSize(width: 300, height: 20),
            attributedString: NSAttributedString(string: "First"),
            accessibility: AccessibilityMetadata(
                label: "First label",
                value: "First value",
                hint: "First help",
                nodeRoleHint: .codeBlock
            )
        )
        let secondLayout = LayoutResult(
            node: ParagraphNode(range: nil, children: []),
            size: CGSize(width: 300, height: 20),
            attributedString: NSAttributedString(string: "Second"),
            accessibility: AccessibilityMetadata(
                label: nil,
                value: nil,
                hint: nil,
                nodeRoleHint: .staticText
            )
        )

        item.configure(with: firstLayout)
        guard let textView = item.view.subviews.first as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertEqual(textView.accessibilityRole(), .group)
        XCTAssertEqual(textView.accessibilityLabel(), "First label")
        XCTAssertEqual(textView.accessibilityValue(), "First value")
        XCTAssertEqual(textView.accessibilityHelp(), "First help")
        XCTAssertTrue(textView.drawsBackground)
        XCTAssertTrue(textView.wantsLayer)

        item.configure(with: secondLayout)

        XCTAssertTrue(textView.isAccessibilityElement())
        XCTAssertEqual(textView.accessibilityRole(), .staticText)
        XCTAssertNil(textView.accessibilityLabel())
        XCTAssertNil(textView.accessibilityValue())
        XCTAssertNil(textView.accessibilityHelp())
        XCTAssertEqual(textView.textStorage?.string, "Second")
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertEqual(textView.layer?.cornerRadius ?? 0, 0)
        XCTAssertEqual(textView.textContainerInset, .zero)
        XCTAssertFalse(textView.wantsLayer)
    }

    func testReconfigureRecyclesHostedView() {
        let item = MarkdownItemView()
        item.loadView()

        let node1 = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "First")])
        let attrStr1 = NSAttributedString(string: "First", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layout1 = LayoutResult(node: node1, size: CGSize(width: 300, height: 20), attributedString: attrStr1)

        let node2 = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Second")])
        let attrStr2 = NSAttributedString(string: "Second", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let layout2 = LayoutResult(node: node2, size: CGSize(width: 300, height: 20), attributedString: attrStr2)

        item.configure(with: layout1)
        XCTAssertEqual(item.view.subviews.count, 1)

        item.configure(with: layout2)
        XCTAssertEqual(item.view.subviews.count, 1,
            "Reconfigure should recycle the single subview instance")

        guard let textView = item.view.subviews[0] as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }
        XCTAssertTrue(textView.textStorage?.string.contains("Second") ?? false,
            "Recycled text view should show new content")
    }

    func testConfigurePrefersContainerWidthOverSolvedWidth() {
        let item = MarkdownItemView()
        item.loadView()
        item.view.frame = NSRect(x: 0, y: 0, width: 400, height: 80)

        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Wrapped text")])
        let attrStr = NSAttributedString(
            string: "Wrapped text",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let layoutResult = LayoutResult(
            node: node,
            size: CGSize(width: 260, height: 60),
            attributedString: attrStr
        )

        item.configure(with: layoutResult)

        guard let textView = item.view.subviews[0] as? NSTextView else {
            XCTFail("Expected NSTextView subview")
            return
        }

        XCTAssertEqual(textView.frame.width, 400, accuracy: 0.5)
        XCTAssertEqual(textView.frame.height, 60, accuracy: 0.5)
    }

    // MARK: - MarkdownCollectionView

    func testInitializesWithScrollViewSubview() {
        let view = MarkdownCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        XCTAssertGreaterThanOrEqual(view.subviews.count, 1,
            "MarkdownCollectionView should contain at least one subview (scrollView)")
        XCTAssertTrue(view.subviews[0] is NSScrollView,
            "First subview should be NSScrollView")
    }

    func testReportsEffectiveContentWidthAfterLayout() {
        let view = MarkdownCollectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        var reportedWidth: CGFloat?
        view.onEffectiveContentWidthChange = { reportedWidth = $0 }

        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(reportedWidth, "Expected the macOS view to report an effective content width")
        XCTAssertEqual(reportedWidth ?? 0, view.effectiveContentWidth, accuracy: 0.5)
        XCTAssertLessThanOrEqual(view.effectiveContentWidth, view.bounds.width)
    }
}
#endif
