import XCTest
import Foundation
@testable import MarkdownKit

/// Verifies `LayoutResult.stableIdentity` is correctly assigned by
/// `LayoutSolver` and behaves as a diffable data source needs:
/// stable under re-parse and same-type content changes, distinct between
/// positions and concrete node types.
final class StableNodeIdentityTests: XCTestCase {

    func testIdentitySurvivesReparseOfIdenticalDocument() async {
        let markdown = """
        # Heading

        First paragraph.

        Second paragraph.
        """

        let parser = MarkdownParser()
        let solver = LayoutSolver()

        let layoutA = await solver.solve(node: parser.parse(markdown), constrainedToWidth: 320)
        let layoutB = await solver.solve(node: parser.parse(markdown), constrainedToWidth: 320)

        XCTAssertEqual(layoutA.children.count, layoutB.children.count)
        for (a, b) in zip(layoutA.children, layoutB.children) {
            XCTAssertEqual(
                a.stableIdentity,
                b.stableIdentity,
                "Re-parsing identical content must produce the same stableIdentity"
            )
        }
    }

    func testSameTopLevelPathAndConcreteTypeRetainsIdentityWhenContentChanges() async {
        let parser = MarkdownParser()
        let solver = LayoutSolver()

        let original = await solver.solve(
            node: parser.parse("# Heading\n\nBody."),
            constrainedToWidth: 320
        )
        let edited = await solver.solve(
            node: parser.parse("# Heading\n\nBody — edited."),
            constrainedToWidth: 320
        )

        XCTAssertEqual(original.children[0].stableIdentity, edited.children[0].stableIdentity)
        XCTAssertTrue(original.children[1].node is ParagraphNode)
        XCTAssertTrue(edited.children[1].node is ParagraphNode)
        XCTAssertEqual(original.children[1].stableIdentity, edited.children[1].stableIdentity)
        XCTAssertNotEqual(original.children[1].renderFingerprint, edited.children[1].renderFingerprint)
    }

    func testSameTopLevelPathWithDifferentConcreteNodeTypeHasDifferentIdentity() async {
        let parser = MarkdownParser()
        let solver = LayoutSolver()

        let paragraph = await solver.solve(
            node: parser.parse("Same text."),
            constrainedToWidth: 320
        )
        let heading = await solver.solve(
            node: parser.parse("# Same text."),
            constrainedToWidth: 320
        )

        XCTAssertEqual(paragraph.children.count, 1)
        XCTAssertEqual(heading.children.count, 1)
        XCTAssertTrue(paragraph.children[0].node is ParagraphNode)
        XCTAssertTrue(heading.children[0].node is HeaderNode)
        XCTAssertNotEqual(paragraph.children[0].stableIdentity, heading.children[0].stableIdentity)
    }

    func testStreamingGrowthOfLastBlockRetainsRowIdentity() async {
        let parser = MarkdownParser()
        let solver = LayoutSolver()

        let before = await solver.solve(
            node: parser.parse("# Heading\n\nStreaming response"),
            constrainedToWidth: 320
        )
        let after = await solver.solve(
            node: parser.parse("# Heading\n\nStreaming response grows token by token."),
            constrainedToWidth: 320
        )

        XCTAssertEqual(before.children.count, 2)
        XCTAssertEqual(after.children.count, 2)
        XCTAssertTrue(before.children[1].node is ParagraphNode)
        XCTAssertTrue(after.children[1].node is ParagraphNode)
        XCTAssertEqual(before.children[1].stableIdentity, after.children[1].stableIdentity)
        XCTAssertNotEqual(before.children[1].renderFingerprint, after.children[1].renderFingerprint)
    }

    func testAppendingContentLeavesLeadingBlockIdentitiesIntact() async {
        // Simulates a streaming append: the user adds a paragraph at the end
        // of the document. Diffable data sources must see "insert at tail",
        // not "replace everything", so leading-block stableIdentities must be
        // preserved.
        let parser = MarkdownParser()
        let solver = LayoutSolver()

        let before = await solver.solve(
            node: parser.parse("# Heading\n\nFirst paragraph."),
            constrainedToWidth: 320
        )
        let after = await solver.solve(
            node: parser.parse("# Heading\n\nFirst paragraph.\n\nSecond paragraph."),
            constrainedToWidth: 320
        )

        XCTAssertEqual(before.children.count, 2)
        XCTAssertEqual(after.children.count, 3)
        // Index 0 and 1 must keep their identity across the append.
        XCTAssertEqual(before.children[0].stableIdentity, after.children[0].stableIdentity)
        XCTAssertEqual(before.children[1].stableIdentity, after.children[1].stableIdentity)
    }

    func testStructurallyIdenticalBlocksAtDifferentPositionsHaveDistinctIdentity() async {
        // Two empty blockquotes shouldn't collide in a diffable data source.
        let parser = MarkdownParser()
        let solver = LayoutSolver()

        let layout = await solver.solve(
            node: parser.parse("""
            > one

            > one
            """),
            constrainedToWidth: 320
        )

        XCTAssertEqual(layout.children.count, 2)
        XCTAssertEqual(
            layout.children[0].node.contentFingerprint,
            layout.children[1].node.contentFingerprint,
            "Sanity: same content → same fingerprint"
        )
        XCTAssertNotEqual(
            layout.children[0].stableIdentity,
            layout.children[1].stableIdentity,
            "Different positions → distinct stableIdentity"
        )
    }

    func testUpdatePlanRetainsPositionedContainerIdentityForDescendantContentChange() {
        let initialParagraph = ParagraphNode(
            range: nil,
            children: [TextNode(range: nil, text: "Nested")]
        )
        let updatedParagraph = ParagraphNode(
            range: nil,
            children: [TextNode(range: nil, text: "Nested content grows")]
        )
        let initial = LayoutResult(
            node: BlockQuoteNode(range: nil, children: [initialParagraph]),
            size: CGSize(width: 320, height: 40),
            children: [
                LayoutResult(
                    node: initialParagraph,
                    size: CGSize(width: 300, height: 20),
                    attributedString: NSAttributedString(string: "Nested")
                )
            ]
        )
        let updated = LayoutResult(
            node: BlockQuoteNode(range: nil, children: [updatedParagraph]),
            size: CGSize(width: 320, height: 80),
            children: [
                LayoutResult(
                    node: updatedParagraph,
                    size: CGSize(width: 300, height: 60),
                    attributedString: NSAttributedString(string: "Nested content grows")
                )
            ]
        )
        let positionedInitial = LayoutResult.positionedTopLevelLayouts([initial])
        let currentOrderedIdentities = positionedInitial.map(\.stableIdentity)
        let previousLayoutsByIdentity = Dictionary(
            uniqueKeysWithValues: positionedInitial.map { ($0.stableIdentity, $0) }
        )

        XCTAssertNotEqual(initial.renderFingerprint, updated.renderFingerprint)
        XCTAssertEqual(currentOrderedIdentities.count, 1)

        let plan = LayoutCollectionUpdatePlan(
            layouts: [updated],
            previousLayoutsByIdentity: previousLayoutsByIdentity,
            currentOrderedIdentities: currentOrderedIdentities,
            hasMainSection: true
        )

        XCTAssertEqual(plan.orderedIdentities, currentOrderedIdentities)
        XCTAssertEqual(plan.changedRetainedIdentities, currentOrderedIdentities)
        XCTAssertTrue(plan.requiresSnapshotApplication)
        XCTAssertTrue(plan.hasRetainedSizeChange)
    }

    func testUnpositionedIdentityUsesContentUntilTopLevelNormalization() {
        let firstNode = ParagraphNode(
            range: nil,
            children: [TextNode(range: nil, text: "First")]
        )
        let secondNode = ParagraphNode(
            range: nil,
            children: [TextNode(range: nil, text: "Second")]
        )
        let first = LayoutResult(node: firstNode, size: .zero)
        let second = LayoutResult(node: secondNode, size: .zero)

        XCTAssertNotEqual(first.stableIdentity, second.stableIdentity)
        XCTAssertEqual(
            first.positionedAtTopLevel(index: 2).stableIdentity,
            second.positionedAtTopLevel(index: 2).stableIdentity
        )
    }

    func testManualTopLevelNormalizationDisambiguatesIdenticalSiblingRows() {
        let node = ParagraphNode(range: nil, children: [TextNode(range: nil, text: "manual row")])
        let first = LayoutResult(
            node: node,
            size: CGSize(width: 320, height: 44),
            attributedString: NSAttributedString(string: "manual row")
        )
        let second = LayoutResult(
            node: node,
            size: CGSize(width: 320, height: 44),
            attributedString: NSAttributedString(string: "manual row")
        )

        XCTAssertEqual(first.stableIdentity, second.stableIdentity)

        let normalized = LayoutResult.positionedTopLevelLayouts([first, second])

        XCTAssertNotEqual(normalized[0].stableIdentity, normalized[1].stableIdentity)
        XCTAssertEqual(
            normalized[0].stableIdentity,
            .topLevel(node: node, index: 0)
        )
        XCTAssertEqual(
            normalized[1].stableIdentity,
            .topLevel(node: node, index: 1)
        )
    }

    func testTopLevelNormalizationMatchesSolverAssignedIdentity() async {
        let parser = MarkdownParser()
        let solver = LayoutSolver()
        let result = await solver.solve(
            node: parser.parse("""
            Paragraph one.

            Paragraph two.
            """),
            constrainedToWidth: 320
        )

        XCTAssertEqual(
            LayoutResult.positionedTopLevelLayouts(result.children).map(\.stableIdentity),
            result.children.map(\.stableIdentity)
        )
    }
}
