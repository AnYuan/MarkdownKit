import XCTest
import Markdown
@testable import MarkdownKit

final class InteractionCacheIdentityTests: XCTestCase {
    private let width: CGFloat = 320

    func testAsyncCacheReturnsCurrentTaskRange() async throws {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let firstRange = sourceRange(line: 2, source: "file:///async.md")
        let secondRange = sourceRange(line: 12, source: "file:///async.md")

        _ = await solver.solve(
            node: taskList(itemRange: firstRange, listRange: sourceRange(line: 1)),
            constrainedToWidth: width
        )
        cache.resetStatsForTesting()
        let second = await solver.solve(
            node: taskList(itemRange: secondRange, listRange: sourceRange(line: 11)),
            constrainedToWidth: width
        )

        XCTAssertEqual(try checkboxData(in: second).range, secondRange)
        XCTAssertEqual(cache.hitCountForTesting, 0)
        XCTAssertEqual(cache.missCountForTesting, 1)
    }

    func testSyncCacheReturnsCurrentTaskRange() throws {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let firstRange = sourceRange(line: 3, source: "file:///sync.md")
        let secondRange = sourceRange(line: 23, source: "file:///sync.md")

        _ = solver.solveSync(
            node: taskList(itemRange: firstRange, listRange: sourceRange(line: 2)),
            constrainedToWidth: width
        )
        cache.resetStatsForTesting()
        let second = solver.solveSync(
            node: taskList(itemRange: secondRange, listRange: sourceRange(line: 22)),
            constrainedToWidth: width
        )

        XCTAssertEqual(try checkboxData(in: second).range, secondRange)
        XCTAssertEqual(cache.hitCountForTesting, 0)
        XCTAssertEqual(cache.missCountForTesting, 1)
    }

    func testSourceURLParticipatesInInteractionCacheIdentity() throws {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let firstRange = sourceRange(line: 4, source: "file:///first.md")
        let secondRange = sourceRange(line: 4, source: "file:///second.md")

        _ = solver.solveSync(
            node: taskList(itemRange: firstRange, listRange: sourceRange(line: 3)),
            constrainedToWidth: width
        )
        cache.resetStatsForTesting()
        let second = solver.solveSync(
            node: taskList(itemRange: secondRange, listRange: sourceRange(line: 3)),
            constrainedToWidth: width
        )

        XCTAssertEqual(try checkboxData(in: second).range, secondRange)
        XCTAssertEqual(cache.hitCountForTesting, 0)
        XCTAssertEqual(cache.missCountForTesting, 1)
    }

    func testSameTaskContentAndRangeHitsCache() throws {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let itemRange = sourceRange(line: 6, source: "file:///same.md")
        let listRange = sourceRange(line: 5, source: "file:///same.md")

        _ = solver.solveSync(
            node: taskList(itemRange: itemRange, listRange: listRange),
            constrainedToWidth: width
        )
        cache.resetStatsForTesting()
        let second = solver.solveSync(
            node: taskList(itemRange: itemRange, listRange: listRange),
            constrainedToWidth: width
        )

        XCTAssertEqual(try checkboxData(in: second).range, itemRange)
        XCTAssertEqual(cache.hitCountForTesting, 1)
        XCTAssertEqual(cache.missCountForTesting, 0)
    }

    func testNoninteractiveRangeChangesStillHitCache() {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let firstList = taskList(
            itemRange: sourceRange(line: 2),
            listRange: sourceRange(line: 1),
            checkbox: .none,
            text: "plain list"
        )
        let secondList = taskList(
            itemRange: sourceRange(line: 22),
            listRange: sourceRange(line: 21),
            checkbox: .none,
            text: "plain list"
        )

        _ = solver.solveSync(node: firstList, constrainedToWidth: width)
        cache.resetStatsForTesting()
        _ = solver.solveSync(node: secondList, constrainedToWidth: width)
        XCTAssertEqual(cache.hitCountForTesting, 1)
        XCTAssertEqual(cache.missCountForTesting, 0)

        let firstParagraph = paragraph(text: "ordinary paragraph", range: sourceRange(line: 30))
        let secondParagraph = paragraph(text: "ordinary paragraph", range: sourceRange(line: 40))
        _ = solver.solveSync(node: firstParagraph, constrainedToWidth: width)
        cache.resetStatsForTesting()
        _ = solver.solveSync(node: secondParagraph, constrainedToWidth: width)
        XCTAssertEqual(cache.hitCountForTesting, 1)
        XCTAssertEqual(cache.missCountForTesting, 0)
    }

    func testDuplicateTaskListsInDocumentKeepTheirOwnRanges() throws {
        let firstRange = sourceRange(line: 2, source: "file:///duplicates.md")
        let secondRange = sourceRange(line: 8, source: "file:///duplicates.md")
        let document = DocumentNode(
            range: sourceRange(line: 1, endLine: 10, source: "file:///duplicates.md"),
            children: [
                taskList(itemRange: firstRange, listRange: sourceRange(line: 1)),
                taskList(itemRange: secondRange, listRange: sourceRange(line: 7))
            ]
        )

        let result = LayoutSolver(cache: LayoutCache()).solveSync(
            node: document,
            constrainedToWidth: width
        )

        XCTAssertEqual(result.children.count, 2)
        XCTAssertEqual(try checkboxData(in: result.children[0]).range, firstRange)
        XCTAssertEqual(try checkboxData(in: result.children[1]).range, secondRange)
    }

    func testInteractionFingerprintPropagatesThroughRenderingAncestors() {
        let first = interactionAncestors(itemRange: sourceRange(line: 5))
        let second = interactionAncestors(itemRange: sourceRange(line: 25))

        XCTAssertNotEqual(first.item._interactionFingerprint, second.item._interactionFingerprint)
        XCTAssertNotEqual(first.nestedList._interactionFingerprint, second.nestedList._interactionFingerprint)
        XCTAssertNotEqual(first.outerItem._interactionFingerprint, second.outerItem._interactionFingerprint)
        XCTAssertNotEqual(first.outerList._interactionFingerprint, second.outerList._interactionFingerprint)
        XCTAssertNotEqual(first.blockQuote._interactionFingerprint, second.blockQuote._interactionFingerprint)
        XCTAssertNotEqual(first.details._interactionFingerprint, second.details._interactionFingerprint)
        XCTAssertNotEqual(first.document._interactionFingerprint, second.document._interactionFingerprint)
    }

    func testClosedDetailsIgnoreHiddenChildInteractionChanges() {
        let first = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: false,
            summary: nil,
            children: [taskList(itemRange: sourceRange(line: 3), listRange: sourceRange(line: 2))]
        )
        let second = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: false,
            summary: nil,
            children: [taskList(itemRange: sourceRange(line: 13), listRange: sourceRange(line: 12))]
        )

        XCTAssertEqual(first.contentFingerprint, second.contentFingerprint)
        XCTAssertEqual(first._interactionFingerprint, second._interactionFingerprint)
        XCTAssertNotNil(first._interactionFingerprint)
    }

    func testRenderedSummaryRangesParticipateInDetailsInteractionIdentity() {
        let firstSummary = SummaryNode(
            range: sourceRange(line: 2),
            children: [TextNode(range: sourceRange(line: 2), text: "Summary")]
        )
        let secondSummary = SummaryNode(
            range: sourceRange(line: 12),
            children: [TextNode(range: sourceRange(line: 12), text: "Summary")]
        )
        let first = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: true,
            summary: firstSummary,
            children: []
        )
        let second = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: true,
            summary: secondSummary,
            children: []
        )

        XCTAssertNotEqual(first._interactionFingerprint, second._interactionFingerprint)
    }

    func testOpenDetailsBodyRangesParticipateInInteractionIdentity() {
        let first = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: true,
            summary: nil,
            children: [paragraph(text: "Body", range: sourceRange(line: 3))]
        )
        let second = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: true,
            summary: nil,
            children: [paragraph(text: "Body", range: sourceRange(line: 13))]
        )

        XCTAssertNotEqual(first._interactionFingerprint, second._interactionFingerprint)
    }

    func testDetailsCacheReturnsCurrentInteractiveNodeRange() {
        let cache = LayoutCache()
        let solver = LayoutSolver(cache: cache)
        let firstRange = sourceRange(line: 2, source: "file:///first-details.md")
        let secondRange = sourceRange(line: 22, source: "file:///second-details.md")
        let summary = SummaryNode(range: nil, children: [TextNode(range: nil, text: "Summary")])

        _ = solver.solveSync(
            node: DetailsNode(range: firstRange, isOpen: false, summary: summary, children: []),
            constrainedToWidth: width
        )
        cache.resetStatsForTesting()
        let second = solver.solveSync(
            node: DetailsNode(range: secondRange, isOpen: false, summary: summary, children: []),
            constrainedToWidth: width
        )

        XCTAssertEqual((second.node as? DetailsNode)?.range, secondRange)
        XCTAssertEqual(cache.hitCountForTesting, 0)
        XCTAssertEqual(cache.missCountForTesting, 1)
    }

    func testRangeOnlyChangeAffectsInteractionDiffButNotRenderingIdentity() {
        let solver = LayoutSolver(cache: LayoutCache())
        let first = solver.solveSync(
            node: taskList(itemRange: sourceRange(line: 2), listRange: sourceRange(line: 1)),
            constrainedToWidth: width
        )
        let second = solver.solveSync(
            node: taskList(itemRange: sourceRange(line: 12), listRange: sourceRange(line: 11)),
            constrainedToWidth: width
        )

        XCTAssertEqual(first.node.contentFingerprint, second.node.contentFingerprint)
        XCTAssertEqual(first.stableIdentity, second.stableIdentity)
        XCTAssertEqual(first.size, second.size)
        XCTAssertEqual(first.renderFingerprint, second.renderFingerprint)
        XCTAssertNotEqual(first.interactionFingerprint, second.interactionFingerprint)
        XCTAssertEqual(
            LayoutResultVariantDiff.changedStableIdentities(
                previous: [first.stableIdentity: first],
                next: [second]
            ),
            [first.stableIdentity]
        )
    }

    func testWithStableIdentityPreservesInteractionFingerprint() {
        let result = LayoutResult(
            node: taskList(
                itemRange: sourceRange(line: 7),
                listRange: sourceRange(line: 6)
            ),
            size: .zero
        )
        let identity = StableNodeIdentity(contentFingerprint: 123, pathHash: 456)

        let stamped = result.withStableIdentity(identity)

        XCTAssertEqual(stamped.stableIdentity, identity)
        XCTAssertEqual(stamped.interactionFingerprint, result.interactionFingerprint)
    }

    func testNilRangeTaskItemHasNoInteractionFingerprint() {
        let item = ListItemNode(
            range: nil,
            checkbox: .checked,
            children: [paragraph(text: "task", range: nil)]
        )
        let list = ListNode(range: sourceRange(line: 1), isOrdered: false, children: [item])

        XCTAssertNil(item._interactionFingerprint)
        XCTAssertNil(list._interactionFingerprint)
    }

    private func sourceRange(
        line: Int,
        endLine: Int? = nil,
        source: String = "file:///document.md"
    ) -> SourceRange {
        let url = URL(string: source)
        return SourceLocation(line: line, column: 2, source: url)
            ..< SourceLocation(line: endLine ?? line, column: 14, source: url)
    }

    private func paragraph(text: String, range: SourceRange?) -> ParagraphNode {
        ParagraphNode(
            range: range,
            children: [TextNode(range: range, text: text)]
        )
    }

    private func taskList(
        itemRange: SourceRange?,
        listRange: SourceRange?,
        checkbox: CheckboxState = .unchecked,
        text: String = "same task"
    ) -> ListNode {
        let item = ListItemNode(
            range: itemRange,
            checkbox: checkbox,
            children: [paragraph(text: text, range: itemRange)]
        )
        return ListNode(range: listRange, isOrdered: false, children: [item])
    }

    private func checkboxData(in result: LayoutResult) throws -> CheckboxInteractionData {
        let attributedString = try XCTUnwrap(result.attributedString)
        return try XCTUnwrap(
            attributedString.attribute(.markdownCheckbox, at: 0, effectiveRange: nil)
                as? CheckboxInteractionData
        )
    }

    private func interactionAncestors(itemRange: SourceRange) -> (
        item: ListItemNode,
        nestedList: ListNode,
        outerItem: ListItemNode,
        outerList: ListNode,
        blockQuote: BlockQuoteNode,
        details: DetailsNode,
        document: DocumentNode
    ) {
        let item = ListItemNode(
            range: itemRange,
            checkbox: .checked,
            children: [paragraph(text: "nested task", range: itemRange)]
        )
        let nestedList = ListNode(
            range: sourceRange(line: 4),
            isOrdered: false,
            children: [item]
        )
        let outerItem = ListItemNode(
            range: sourceRange(line: 3),
            checkbox: .none,
            children: [nestedList]
        )
        let outerList = ListNode(
            range: sourceRange(line: 2),
            isOrdered: false,
            children: [outerItem]
        )
        let blockQuote = BlockQuoteNode(range: sourceRange(line: 1), children: [outerList])
        let details = DetailsNode(
            range: sourceRange(line: 1),
            isOpen: true,
            summary: nil,
            children: [blockQuote]
        )
        let document = DocumentNode(range: sourceRange(line: 1), children: [details])
        return (item, nestedList, outerItem, outerList, blockQuote, details, document)
    }
}
