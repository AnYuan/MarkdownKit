import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit
import Markdown

@MainActor
final class UIComponentsPlatformTests: XCTestCase {

    // MARK: - AsyncCodeView

    func testAsyncCodeViewHasSubviews() {
        let view = AsyncCodeView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        // Should have textView + copyButton as subviews
        XCTAssertEqual(view.subviews.count, 2)
    }

    func testAsyncCodeViewLayoutSubviews() {
        let view = AsyncCodeView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        view.layoutSubviews()

        // TextView should be inset by padding (16)
        let textView = view.subviews.first(where: { $0 is AsyncTextView })
        XCTAssertNotNil(textView)
        XCTAssertEqual(textView?.frame.origin.x, 16)
        XCTAssertEqual(textView?.frame.origin.y, 16)
    }

    func testAsyncCodeViewResolvesRetainedThemeForLayoutAppearance() {
        let node = CodeBlockNode(range: nil, language: "swift", code: "let value = 1")
        let layout = LayoutResult(
            node: node,
            size: CGSize(width: 300, height: 100),
            attributedString: NSAttributedString(string: node.code),
            appearance: .dark
        )
        let view = AsyncCodeView(frame: CGRect(origin: .zero, size: layout.size))

        view.configure(with: layout)

        XCTAssertEqual(
            view.backgroundColor,
            Theme.default.resolved(for: .dark).colors.codeColor.background
        )
    }

    // MARK: - AsyncTextView

    func testAsyncTextViewConfigureWithNilString() {
        let node = TextNode(range: nil, text: "")
        let layout = LayoutResult(node: node, size: CGSize(width: 200, height: 50), attributedString: nil)

        let view = AsyncTextView(frame: .zero)
        view.configure(with: layout)

        // Should clear layer contents and not crash
        XCTAssertNil(view.layer.contents)
    }

    // MARK: - MarkdownCollectionViewCell Routing

    func testCollectionViewRecalculatesExistingRowHeight() async throws {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "Resizable")])
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let initial = LayoutResult(node: node, size: CGSize(width: 320, height: 40))
        let resized = LayoutResult(node: node, size: CGSize(width: 320, height: 80))

        view.layouts = [initial]
        await Task.yield()
        view.layoutIfNeeded()

        let collectionView = try XCTUnwrap(view.subviews.compactMap { $0 as? UICollectionView }.first)
        collectionView.layoutIfNeeded()
        XCTAssertEqual(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )?.size.height,
            40
        )

        view.layouts = [resized]
        await Task.yield()
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        XCTAssertEqual(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )?.size.height,
            80
        )
    }

    func testCollectionViewSkipsEquivalentSnapshotsAndRefreshesLookup() async throws {
        let emptyView = makeCollectionView()
        let emptyCollectionView = try collectionView(in: emptyView)

        emptyView.layouts = []
        await Task.yield()
        XCTAssertEqual(emptyView.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(emptyView.layoutSnapshotSkipCountForTesting, 0)
        XCTAssertEqual(emptyCollectionView.numberOfSections, 1)
        XCTAssertEqual(emptyCollectionView.numberOfItems(inSection: 0), 0)

        emptyView.layouts = []
        await Task.yield()
        XCTAssertEqual(emptyView.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(emptyView.layoutSnapshotSkipCountForTesting, 1)

        let view = makeCollectionView()
        let initial = [makeLayout("A"), makeLayout("B")]
        view.layouts = initial
        await Task.yield()
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 0)

        view.layouts = initial
        await Task.yield()
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 1)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 0)

        let equivalent = [makeLayout("A"), makeLayout("B")]
        view.layouts = equivalent
        await Task.yield()
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

    func testCollectionViewAppliesStructuralUpdatesOnce() async throws {
        let view = makeCollectionView()
        let collectionView = try collectionView(in: view)

        view.layouts = [makeLayout("A"), makeLayout("B")]
        await Task.yield()
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)

        view.layouts = [makeLayout("A"), makeLayout("B"), makeLayout("C")]
        await Task.yield()
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 2)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 0)

        view.layouts = [makeLayout("C"), makeLayout("A"), makeLayout("B")]
        await Task.yield()
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 3)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 3)

        view.layouts = [makeLayout("C"), makeLayout("D"), makeLayout("B")]
        await Task.yield()
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

    func testCollectionViewReconfiguresVisibleSameTypeGrowingRowWithoutReuse() async throws {
        let view = makeCollectionView()
        let collectionView = try collectionView(in: view)
        let initial = makeLayout("Streaming")

        await applyLayoutsAndWait([initial], to: view)
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let initialCell = try XCTUnwrap(
            collectionView.cellForItem(at: indexPath) as? MarkdownCollectionViewCell
        )
        let initialHostedView = try XCTUnwrap(
            initialCell.contentView.subviews.first as? AsyncTextView
        )
        let initialReuseCount = initialHostedView.prepareForReuseCountForTesting
        let initialSnapshotApplicationCount = view.layoutSnapshotApplicationCountForTesting
        let updatedText = "Streaming response grows token by token."
        let updated = makeLayout(
            updatedText,
            size: CGSize(width: 320, height: 80)
        )

        await applyLayoutsAndWait([updated], to: view)
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        XCTAssertEqual(
            view.layoutSnapshotApplicationCountForTesting,
            initialSnapshotApplicationCount + 1
        )
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 1)
        XCTAssertEqual(
            view.layoutResult(forIndexPath: indexPath)?.attributedString?.string,
            updatedText
        )

        let currentCell = try XCTUnwrap(
            collectionView.cellForItem(at: indexPath) as? MarkdownCollectionViewCell
        )
        let currentHostedView = try XCTUnwrap(
            currentCell.contentView.subviews.first as? AsyncTextView
        )
        XCTAssertIdentical(currentCell, initialCell)
        XCTAssertIdentical(currentHostedView, initialHostedView)
        XCTAssertEqual(currentHostedView.currentAttributedString?.string, updatedText)
        XCTAssertEqual(
            currentHostedView.prepareForReuseCountForTesting,
            initialReuseCount
        )
    }

    func testCollectionViewAppliesEachRetainedVariantOnce() async {
        let baseRange = sourceRange(line: 1)
        let baseSize = CGSize(width: 320, height: 40)

        await assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 10),
            to: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 11),
            expectsLayoutInvalidation: false
        )
        await assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, appearance: .light, renderFingerprint: 10),
            to: makeListItemLayout(range: baseRange, size: baseSize, appearance: .dark, renderFingerprint: 10),
            expectsLayoutInvalidation: false
        )
        await assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 10),
            to: makeListItemLayout(
                range: baseRange,
                size: CGSize(width: 320, height: 80),
                renderFingerprint: 10
            ),
            expectsLayoutInvalidation: true
        )
        await assertVariantUpdate(
            from: makeListItemLayout(range: baseRange, size: baseSize, renderFingerprint: 10),
            to: makeListItemLayout(range: sourceRange(line: 2), size: baseSize, renderFingerprint: 10),
            expectsLayoutInvalidation: false
        )
    }

    func testVisibleCellCallbacksUseLatestHandlersWhenEquivalentSnapshotIsSkipped() async throws {
        let view = makeCollectionView()
        let collectionView = try collectionView(in: view)
        var handlerALinkCount = 0
        var handlerACheckboxCount = 0
        var handlerBLinkCount = 0
        var handlerBCheckboxCount = 0

        view.onLinkTap = { _ in handlerALinkCount += 1 }
        view.onCheckboxToggle = { _ in handlerACheckboxCount += 1 }
        view.layouts = [makeListItemLayout(range: sourceRange(line: 1), renderFingerprint: 10)]
        await Task.yield()
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let cell = try XCTUnwrap(
            collectionView.cellForItem(at: IndexPath(item: 0, section: 0))
                as? MarkdownCollectionViewCell
        )

        view.onLinkTap = { _ in handlerBLinkCount += 1 }
        view.onCheckboxToggle = { _ in handlerBCheckboxCount += 1 }
        view.layouts = [makeListItemLayout(range: sourceRange(line: 1), renderFingerprint: 10)]
        await Task.yield()
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 1)

        cell.onLinkTap?(try XCTUnwrap(URL(string: "https://example.com")))
        cell.onCheckboxToggle?(
            CheckboxInteractionData(isChecked: true, range: sourceRange(line: 1))
        )

        XCTAssertEqual(handlerALinkCount, 0)
        XCTAssertEqual(handlerACheckboxCount, 0)
        XCTAssertEqual(handlerBLinkCount, 1)
        XCTAssertEqual(handlerBCheckboxCount, 1)
    }

    func testSelectableTextViewRelaysOnlyDefaultLinkAction() throws {
        let textView = SelectableTextView(frame: .zero)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        var tappedURLs: [URL] = []
        textView.onLinkTap = { tappedURLs.append($0) }

        XCTAssertTrue(
            textView.textView(
                textView,
                shouldInteractWith: url,
                in: NSRange(location: 0, length: 1),
                interaction: .preview
            )
        )
        XCTAssertTrue(tappedURLs.isEmpty)

        XCTAssertFalse(
            textView.textView(
                textView,
                shouldInteractWith: url,
                in: NSRange(location: 0, length: 1),
                interaction: .invokeDefaultAction
            )
        )
        XCTAssertEqual(tappedURLs, [url])
    }

    func testCellRoutesCodeBlockToAsyncCodeView() {
        let codeNode = CodeBlockNode(range: nil, language: "swift", code: "let x = 1")
        let layout = LayoutResult(node: codeNode, size: CGSize(width: 320, height: 100))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncCodeView)
    }

    func testCellRoutesDefaultNodeToAsyncTextView() {
        let textNode = ParagraphNode(range: nil, children: [])
        let layout = LayoutResult(node: textNode, size: CGSize(width: 320, height: 50))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncTextView)
    }

    func testCellReconfigurePurgesOldView() {
        let textNode = ParagraphNode(range: nil, children: [])
        let textLayout = LayoutResult(node: textNode, size: CGSize(width: 320, height: 50))

        let codeNode = CodeBlockNode(range: nil, language: nil, code: "x")
        let codeLayout = LayoutResult(node: codeNode, size: CGSize(width: 320, height: 100))

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: textLayout)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncTextView)

        cell.configure(with: codeLayout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertTrue(cell.contentView.subviews[0] is AsyncCodeView)
    }

    func testCellPrepareForReuseRetainsHostedViewAndClearsState() {
        let textNode = ParagraphNode(range: nil, children: [])
        let attributedString = NSAttributedString(string: "Reusable text")
        let layout = LayoutResult(
            node: textNode,
            size: CGSize(width: 320, height: 50),
            attributedString: attributedString
        )

        let cell = MarkdownCollectionViewCell(frame: .zero)
        cell.configure(with: layout)

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        guard let hostedView = cell.contentView.subviews.first as? AsyncTextView else {
            XCTFail("Expected AsyncTextView after configure")
            return
        }
        XCTAssertEqual(hostedView.currentAttributedString?.string, attributedString.string)

        cell.onLinkTap = { _ in }
        cell.onCheckboxToggle = { _ in }
        cell.onDetailsTap = { _ in }
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = "stale"
        cell.accessibilityValue = "stale"
        cell.accessibilityHint = "stale"
        cell.accessibilityTraits = .link

        cell.prepareForReuse()

        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertIdentical(cell.contentView.subviews.first, hostedView)
        XCTAssertNil(hostedView.currentAttributedString)
        XCTAssertNil(cell.onLinkTap)
        XCTAssertNil(cell.onCheckboxToggle)
        XCTAssertNil(cell.onDetailsTap)
        XCTAssertFalse(cell.isAccessibilityElement)
        XCTAssertNil(cell.accessibilityLabel)
        XCTAssertNil(cell.accessibilityValue)
        XCTAssertNil(cell.accessibilityHint)
        XCTAssertEqual(cell.accessibilityTraits, .none)

        cell.configure(with: layout)
        XCTAssertEqual(cell.contentView.subviews.count, 1)
        XCTAssertIdentical(cell.contentView.subviews.first, hostedView)
        XCTAssertEqual(hostedView.currentAttributedString?.string, attributedString.string)
    }

    private func makeCollectionView() -> MarkdownCollectionView {
        MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    }

    private func collectionView(in view: MarkdownCollectionView) throws -> UICollectionView {
        try XCTUnwrap(view.subviews.compactMap { $0 as? UICollectionView }.first)
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
        expectsLayoutInvalidation: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let view = makeCollectionView()
        await applyLayoutsAndWait([initial], to: view)
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 1, file: file, line: line)
        XCTAssertEqual(view.layoutInvalidationRequestCountForTesting, 0, file: file, line: line)

        await applyLayoutsAndWait([updated], to: view)
        XCTAssertEqual(view.layoutSnapshotApplicationCountForTesting, 2, file: file, line: line)
        XCTAssertEqual(view.layoutSnapshotSkipCountForTesting, 0, file: file, line: line)
        XCTAssertEqual(view.lastLayoutChangedIdentityCountForTesting, 1, file: file, line: line)
        XCTAssertEqual(
            view.layoutInvalidationRequestCountForTesting,
            expectsLayoutInvalidation ? 1 : 0,
            file: file,
            line: line
        )
    }

    private func applyLayoutsAndWait(
        _ layouts: [LayoutResult],
        to view: MarkdownCollectionView
    ) async {
        let applied = expectation(description: "Diffable snapshot application completed")
        view.onLayoutSnapshotApplicationCompletionForTesting = {
            applied.fulfill()
        }
        view.layouts = layouts
        await fulfillment(of: [applied], timeout: 2)
        view.onLayoutSnapshotApplicationCompletionForTesting = nil
    }
}
#endif
