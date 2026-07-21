import XCTest
@testable import MarkdownKit

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import Markdown

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

    func testCollectionViewSkipsEquivalentSnapshotsAndRefreshesLookup() throws {
        let emptyView = makeCollectionView()
        let emptyCollectionView = try collectionView(in: emptyView)

        emptyView.layouts = []
        XCTAssertEqual(emptyView.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(emptyView.layoutSnapshotSkipCountForTesting, 0)
        XCTAssertEqual(emptyCollectionView.numberOfSections, 1)
        XCTAssertEqual(emptyCollectionView.numberOfItems(inSection: 0), 0)

        emptyView.layouts = []
        XCTAssertEqual(emptyView.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(emptyView.layoutSnapshotSkipCountForTesting, 1)

        let view = makeCollectionView()
        let initial = [makeLayout("A"), makeLayout("B")]
        view.layouts = initial
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 0)

        view.layouts = initial
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 1)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 0)

        let equivalent = [makeLayout("A"), makeLayout("B")]
        view.layouts = equivalent
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 2)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 0)

        let latestA = try XCTUnwrap(view.layoutResult(forIndexPath: IndexPath(item: 0, section: 0)))
        let latestB = try XCTUnwrap(view.layoutResult(forIndexPath: IndexPath(item: 1, section: 0)))
        XCTAssertEqual(latestA.node.id, equivalent[0].node.id)
        XCTAssertEqual(latestB.node.id, equivalent[1].node.id)
        XCTAssertNotEqual(latestA.node.id, initial[0].node.id)
        XCTAssertNotEqual(latestB.node.id, initial[1].node.id)
    }

    func testCollectionViewAppliesStructuralUpdatesOnce() throws {
        let view = makeCollectionView()
        let collectionView = try collectionView(in: view)

        view.layouts = [makeLayout("A"), makeLayout("B")]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)

        view.layouts = [makeLayout("A"), makeLayout("B"), makeLayout("C")]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 2)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 0)

        view.layouts = [makeLayout("C"), makeLayout("A"), makeLayout("B")]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 3)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 3)

        view.layouts = [makeLayout("C"), makeLayout("D"), makeLayout("B")]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 4)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 1)
        XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 3)
        XCTAssertEqual(
            try (0..<3).map {
                let layout = try XCTUnwrap(
                    view.layoutResult(forIndexPath: IndexPath(item: $0, section: 0))
                )
                return try XCTUnwrap(layout.attributedString?.string)
            },
            ["C", "D", "B"]
        )
    }

    func testCollectionViewAppliesSameTypeGrowingRowAsRetainedChange() throws {
        let view = makeCollectionView()
        let collectionView = try collectionView(in: view)
        let initial = makeLayout("Streaming")

        view.layouts = [initial]
        let initialSnapshotApplicationCount = view.layoutSnapshotApplicationCountForTesting
        view.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
        let initialItem = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 0, section: 0)) as? MarkdownItemView
        )
        let initialTextView = try XCTUnwrap(initialItem.view.subviews.first as? NSTextView)
        XCTAssertEqual(initialTextView.textStorage?.string, "Streaming")

        let updatedText = "Streaming response grows token by token."
        let updated = makeLayout(
            updatedText,
            size: CGSize(width: 320, height: 80)
        )

        view.layouts = [updated]

        XCTAssertEqual(
            view.layoutSnapshotApplicationCountForTesting,
            initialSnapshotApplicationCount + 1
        )
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 1)
        let latest = try XCTUnwrap(
            view.layoutResult(forIndexPath: IndexPath(item: 0, section: 0))
        )
        XCTAssertEqual(latest.attributedString?.string, updatedText)

        view.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
        let item = try XCTUnwrap(
            collectionView.item(at: IndexPath(item: 0, section: 0)) as? MarkdownItemView
        )
        let textView = try XCTUnwrap(item.view.subviews.first as? NSTextView)
        XCTAssertEqual(textView.textStorage?.string, updatedText)
        XCTAssertEqual(item.view.frame.height, updated.size.height)
    }

    func testCollectionViewAppliesEachRetainedVariantOnce() {
        let baseRange = sourceRange(line: 1)
        let baseSize = CGSize(width: 320, height: 40)

        assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 10),
            to: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 11)
        )
        assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, appearance: .light, renderFingerprint: 10),
            to: makeListItemLayout(range: baseRange, size: baseSize, appearance: .dark, renderFingerprint: 10)
        )
        assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 10),
            to: makeListItemLayout(
                range: baseRange,
                size: CGSize(width: 320, height: 80),
                renderFingerprint: 10
            )
        )
        assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 10),
            to: makeListItemLayout(range: sourceRange(line: 2), size: baseSize, renderFingerprint: 10)
        )
    }

    func testCollectionViewReloadsEquivalentLayoutsAfterThemeChange() {
        let view = makeCollectionView()
        view.layouts = [makeCodeLayout()]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)

        let base = Theme.default
        view.theme = Theme(
            typography: base.typography,
            colors: Theme.Colors(
                textColor: base.colors.textColor,
                codeColor: ColorToken(foreground: .white, background: .magenta),
                inlineCodeColor: base.colors.inlineCodeColor,
                tableColor: base.colors.tableColor,
                linkColor: base.colors.linkColor,
                blockQuoteColor: base.colors.blockQuoteColor,
                thematicBreakColor: base.colors.thematicBreakColor
            )
        )
        view.layouts = [makeCodeLayout()]

        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 2)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 0)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 0)
    }

    private func makeCollectionView() -> MarkdownCollectionView {
        MarkdownCollectionView(frame: NSRect(x: 0, y: 0, width: 320, height: 480))
    }

    private func collectionView(in view: MarkdownCollectionView) throws -> NSCollectionView {
        let scrollView = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        return try XCTUnwrap(scrollView.documentView as? NSCollectionView)
    }

    private func makeLayout(
        _ text: String,
        size: CGSize = CGSize(width: 320, height: 40)
    ) -> LayoutResult {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: text)])
        return LayoutResult(
            node: node,
            size: size,
            attributedString: NSAttributedString(string: text)
        )
    }

    private func makeCodeLayout() -> LayoutResult {
        let node = CodeBlockNode(range: nil, language: "swift", code: "let value = 1")
        return LayoutResult(
            node: node,
            size: CGSize(width: 320, height: 80),
            attributedString: NSAttributedString(string: node.code)
        )
    }

    private func makeListItemLayout(
        range: SourceRange?,
        size: CGSize = CGSize(width: 320, height: 40),
        appearance: MarkdownAppearance = .light,
        renderFingerprint: Int
    ) -> LayoutResult {
        LayoutResult(
            node: ListItemNode(
                range: range,
                checkbox: .unchecked,
                children: [TextNode(range: nil, text: "Task")]
            ),
            size: size,
            attributedString: NSAttributedString(string: "Task"),
            appearance: appearance,
            renderFingerprint: renderFingerprint
        )
    }

    private func sourceRange(line: Int) -> SourceRange {
        SourceRange(
            start: SourceLocation(line: line, column: 1, source: nil),
            end: SourceLocation(line: line, column: 8, source: nil)
        )
    }

    private func assertVariantUpdate(
        from initial: LayoutResult,
        to updated: LayoutResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let view = makeCollectionView()
        view.layouts = [initial]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1, file: file, line: line)

        view.layouts = [updated]
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 2, file: file, line: line)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 0, file: file, line: line)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 1, file: file, line: line)
    }
}
#endif
