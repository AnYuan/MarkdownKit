import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TestHelper {
    /// Parse markdown string and return the DocumentNode.
    static func parse(_ markdown: String) -> DocumentNode {
        let parser = MarkdownParser()
        return parser.parse(markdown)
    }

    /// Parse with custom plugins.
    static func parse(_ markdown: String, plugins: [ASTPlugin]) -> DocumentNode {
        let parser = MarkdownParser(plugins: plugins)
        return parser.parse(markdown)
    }

    /// Parse and solve layout in one call.
    static func solveLayout(
        _ markdown: String,
        width: CGFloat = 400.0,
        theme: Theme = .default,
        plugins: [ASTPlugin] = [],
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) async -> LayoutResult {
        let doc = parse(markdown, plugins: plugins)
        let solver = LayoutSolver(theme: theme, imageLoadingPolicy: imageLoadingPolicy)
        return await solver.solve(node: doc, constrainedToWidth: width)
    }

    /// Assert a child at index is a specific node type and return it.
    @discardableResult
    static func assertChild<T: MarkdownNode>(
        _ parent: MarkdownNode,
        at index: Int,
        is _: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T? {
        XCTAssertGreaterThan(parent.children.count, index,
            "Expected at least \(index + 1) children, got \(parent.children.count)",
            file: file, line: line)
        guard parent.children.count > index else { return nil }
        let child = parent.children[index] as? T
        XCTAssertNotNil(child,
            "Expected child[\(index)] to be \(T.self), got \(type(of: parent.children[index]))",
            file: file, line: line)
        return child
    }
}
