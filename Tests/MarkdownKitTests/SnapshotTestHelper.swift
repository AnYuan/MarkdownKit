import Foundation
@testable import MarkdownKit

#if os(macOS)
import AppKit

@MainActor
enum SnapshotTestHelper {
    private static let stableAppearance = NSAppearance(named: .aqua)!

    static func withStableAppearance(_ body: () -> Void) {
        stableAppearance.performAsCurrentDrawingAppearance(body)
    }

    static func solveReferenceLayout(
        markdown: String,
        constrainedToWidth width: CGFloat
    ) -> LayoutResult {
        var result: LayoutResult!

        // AppKit appearance is thread-local, so this test-only reference path
        // keeps layout color resolution inside one synchronous Aqua scope.
        // Production rendering remains on its asynchronous path.
        withStableAppearance {
            let document = MarkdownParser().parse(markdown)
            result = LayoutSolver().solveSync(
                node: document,
                constrainedToWidth: width
            )
        }

        return result
    }

    static func applyStableAppearance(to view: NSView) {
        view.appearance = stableAppearance
    }

    static func makeStableContainer(size: CGSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        applyStableAppearance(to: container)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        return container
    }
}
#endif
