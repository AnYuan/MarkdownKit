import XCTest
import SnapshotTesting
import Markdown
@testable import MarkdownKit

#if os(macOS)
import AppKit

@MainActor
final class SnapshotTests: XCTestCase {
    // Committed visual comparison and same-environment determinism use the
    // same strict thresholds. The perceptual margin only tolerates
    // imperceptible antialiasing jitter.
    private let imagePrecision: Float = 0.998
    private let imagePerceptualPrecision: Float = 0.99

    private var imageStrategy: Snapshotting<NSView, NSImage> {
        .image(
            precision: imagePrecision,
            perceptualPrecision: imagePerceptualPrecision
        )
    }

    func testTableRendering() {
        SnapshotTestHelper.withStableAppearance {
            let markdown = """
            | Header 1 | Header 2 |
            | :--- | ---: |
            | Row 1 left | Row 1 right |
            | Row 2 left | Row 2 right |
            """

            let layoutRoot = SnapshotTestHelper.solveReferenceLayout(
                markdown: markdown,
                constrainedToWidth: 400
            )
            guard let layout = layoutRoot.children.first else {
                XCTFail("No child layout generated")
                return
            }

            XCTAssertGreaterThan(layout.size.width, 0)
            XCTAssertGreaterThan(layout.size.height, 0)

            let item = MarkdownItemView()
            item.loadView()
            SnapshotTestHelper.applyStableAppearance(to: item.view)
            let container = SnapshotTestHelper.makeStableContainer(size: layout.size)

            item.view.frame = NSRect(origin: .zero, size: layout.size)
            item.configure(with: layout)
            container.addSubview(item.view)

            assertSnapshot(of: container, as: imageStrategy)
        }
    }
    
    func testCodeBlockRendering() {
        SnapshotTestHelper.withStableAppearance {
            let markdown = """
            ```swift
            func hello() {
                print("World")
            }
            ```
            """

            let layoutRoot = SnapshotTestHelper.solveReferenceLayout(
                markdown: markdown,
                constrainedToWidth: 400
            )
            guard let layout = layoutRoot.children.first else {
                XCTFail("No child layout generated")
                return
            }

            XCTAssertGreaterThan(layout.size.width, 0)
            XCTAssertGreaterThan(layout.size.height, 0)

            let item = MarkdownItemView()
            item.loadView()
            SnapshotTestHelper.applyStableAppearance(to: item.view)
            let container = SnapshotTestHelper.makeStableContainer(size: layout.size)

            item.view.frame = NSRect(origin: .zero, size: layout.size)
            item.configure(with: layout)
            container.addSubview(item.view)

            assertSnapshot(of: container, as: imageStrategy)
        }
    }

    func testMathRendering() {
        SnapshotTestHelper.withStableAppearance {
            let markdown = """
            Block math:

            $$
            e^{i\\pi} + 1 = 0
            $$

            Inline math: $E=mc^2$
            """

            let layoutRoot = SnapshotTestHelper.solveReferenceLayout(
                markdown: markdown,
                constrainedToWidth: 400
            )

            let totalHeight = layoutRoot.children.reduce(0) { $0 + $1.size.height }
            let container = SnapshotTestHelper.makeStableContainer(
                size: CGSize(width: 400, height: totalHeight)
            )

            var currentY: CGFloat = totalHeight
            for childLayout in layoutRoot.children {
                let item = MarkdownItemView()
                item.loadView()
                SnapshotTestHelper.applyStableAppearance(to: item.view)

                item.view.frame = NSRect(
                    x: 0,
                    y: currentY - childLayout.size.height,
                    width: childLayout.size.width,
                    height: childLayout.size.height
                )
                item.configure(with: childLayout)
                currentY -= childLayout.size.height
                container.addSubview(item.view)
            }

            assertSnapshot(of: container, as: imageStrategy)
        }
    }
    
    func testTasklistRendering() {
        SnapshotTestHelper.withStableAppearance {
            let markdown = """
            - [ ] Unfinished Task
            - [x] Finished Task
            - Standard Bullet
            """

            let layoutRoot = SnapshotTestHelper.solveReferenceLayout(
                markdown: markdown,
                constrainedToWidth: 400
            )

            guard let layout = layoutRoot.children.first else {
                XCTFail()
                return
            }

            let item = MarkdownItemView()
            item.loadView()
            SnapshotTestHelper.applyStableAppearance(to: item.view)
            let container = SnapshotTestHelper.makeStableContainer(size: layout.size)

            item.view.frame = NSRect(origin: .zero, size: layout.size)
            item.configure(with: layout)
            container.addSubview(item.view)

            assertSnapshot(of: container, as: imageStrategy)
        }
    }
}
#endif
