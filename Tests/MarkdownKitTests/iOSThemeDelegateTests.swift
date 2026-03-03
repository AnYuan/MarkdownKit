import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

private final class MockThemeDelegate: MarkdownCollectionViewThemeDelegate {
    var reloadCount = 0
    var lastView: MarkdownCollectionView?

    func markdownCollectionViewDidRequestThemeReload(_ view: MarkdownCollectionView) {
        reloadCount += 1
        lastView = view
    }
}

@MainActor
final class iOSThemeDelegateTests: XCTestCase {

    func testDelegatePropertyIsWeak() {
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        autoreleasepool {
            let delegate = MockThemeDelegate()
            view.themeDelegate = delegate
            XCTAssertNotNil(view.themeDelegate)
        }
        // Delegate should be deallocated since it's weak
        XCTAssertNil(view.themeDelegate)
    }

    func testDelegateCalledOnTraitChange() {
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let delegate = MockThemeDelegate()
        view.themeDelegate = delegate

        // Passing nil as previous trait collection causes hasDifferentColorAppearance to return true
        view.traitCollectionDidChange(nil)

        XCTAssertEqual(delegate.reloadCount, 1)
        XCTAssertTrue(delegate.lastView === view)
    }

    func testDelegateNotCalledWhenSameTraits() {
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let delegate = MockThemeDelegate()
        view.themeDelegate = delegate

        // Same trait collection should not trigger reload
        view.traitCollectionDidChange(view.traitCollection)

        XCTAssertEqual(delegate.reloadCount, 0)
    }

    func testNoDelegateNoCrash() {
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        // No delegate set — optional chaining should handle gracefully
        view.traitCollectionDidChange(nil)
        // If we reach here, no crash occurred
    }

    func testLayoutsPropertySetter() {
        let view = MarkdownCollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        // Setting empty layouts should not crash
        view.layouts = []
        XCTAssertEqual(view.layouts.count, 0)
    }
}
#endif
