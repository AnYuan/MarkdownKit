import XCTest
import Foundation
@testable import MarkdownKit

/// Verifies `LayoutResult.stableIdentity` is correctly assigned by
/// `LayoutSolver` and behaves as a diffable data source needs:
/// stable under re-parse, distinct between positions, distinct between content.
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

    func testIdentityChangesWhenContentChanges() async {
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

        // The heading is unchanged → same identity. The paragraph changed →
        // different identity.
        XCTAssertEqual(original.children[0].stableIdentity, edited.children[0].stableIdentity)
        XCTAssertNotEqual(original.children[1].stableIdentity, edited.children[1].stableIdentity)
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
            StableNodeIdentity(
                contentFingerprint: node.contentFingerprint,
                pathHash: StableNodeIdentity.pathHash(for: [0])
            )
        )
        XCTAssertEqual(
            normalized[1].stableIdentity,
            StableNodeIdentity(
                contentFingerprint: node.contentFingerprint,
                pathHash: StableNodeIdentity.pathHash(for: [1])
            )
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
