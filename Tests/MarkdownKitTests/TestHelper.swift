import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TestHelper {
    private static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAADa6r/EAAAADUlEQVQIHWNwrL32HwAFKwKUyeNl6wAAAABJRU5ErkJggg=="

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
        imageLoadingPolicy: ImageLoadingPolicy = .default,
        appearance: MarkdownAppearance = .light
    ) async -> LayoutResult {
        let doc = parse(markdown, plugins: plugins)
        let solver = LayoutSolver(theme: theme, imageLoadingPolicy: imageLoadingPolicy, appearance: appearance)
        return await solver.solve(node: doc, constrainedToWidth: width)
    }

    static func onePixelPNGData() throws -> Data {
        guard let data = Data(base64Encoded: onePixelPNGBase64) else {
            throw TestFixtureError.invalidPNGData
        }
        return data
    }

    /// Asserts a diagnostic counter's real value in Debug and its compiled-out
    /// zero value in Release.
    static func assertDebugCounter(
        _ actual: @autoclosure () -> Int,
        equals debugExpected: Int,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if DEBUG
        XCTAssertEqual(actual(), debugExpected, message(), file: file, line: line)
        #else
        XCTAssertEqual(actual(), 0, message(), file: file, line: line)
        #endif
    }

    static func assertDebugCounter(
        _ actual: @autoclosure () -> Int,
        greaterThan debugMinimum: Int,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if DEBUG
        XCTAssertGreaterThan(actual(), debugMinimum, message(), file: file, line: line)
        #else
        XCTAssertEqual(actual(), 0, message(), file: file, line: line)
        #endif
    }

    static func assertDebugCounter(
        _ actual: @autoclosure () -> Int,
        greaterThanOrEqual debugMinimum: Int,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if DEBUG
        XCTAssertGreaterThanOrEqual(actual(), debugMinimum, message(), file: file, line: line)
        #else
        XCTAssertEqual(actual(), 0, message(), file: file, line: line)
        #endif
    }

    static func flattenedLayoutText(from layouts: [LayoutResult]) -> String {
        var pieces: [String] = []
        for layout in layouts {
            collectText(from: layout, into: &pieces)
        }
        return pieces.joined(separator: "\n")
    }

    private static func collectText(from layout: LayoutResult, into pieces: inout [String]) {
        if let attributed = layout.attributedString, !attributed.string.isEmpty {
            pieces.append(attributed.string)
        } else if let text = layout.node as? TextNode {
            pieces.append(text.text)
        }

        for child in layout.children {
            collectText(from: child, into: &pieces)
        }
    }

    #if canImport(UIKit) && !os(watchOS)
    static func imageContainsVisibleNonWhitePixel(_ image: CGImage?) -> Bool {
        guard let image else { return false }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 0, to: data.count, by: 4) {
            let red = data[index]
            let green = data[index + 1]
            let blue = data[index + 2]
            let alpha = data[index + 3]
            if alpha > 0, red < 250 || green < 250 || blue < 250 {
                return true
            }
        }

        return false
    }
    #endif

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

    struct BlockingDiagramAdapter: DiagramRenderingAdapter {
        private let output: String
        private let state: BlockingResourceState

        init(output: String, blockOnRender: Int = 1) {
            self.output = output
            self.state = BlockingResourceState(blockOnRender: blockOnRender)
        }

        func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
            await state.recordRender(source: source)
            return NSAttributedString(string: output)
        }

        func waitUntilFirstRenderStarts() async -> Bool {
            await state.waitUntilRenderStarts(1)
        }

        func waitUntilBlockedRenderStarts() async -> Bool {
            await state.waitUntilBlockedRenderStarts()
        }

        func releaseFirstRender() async {
            await releaseBlockedRender()
        }

        func releaseBlockedRender() async {
            await state.releaseBlockedRender()
        }

        func renderCount() async -> Int {
            await state.renderCount
        }

        func renderedSources() async -> [String] {
            await state.renderedSources
        }

        func cacheFingerprint(into hasher: inout Hasher) {
            hasher.combine("BlockingDiagramAdapter")
            hasher.combine(output)
        }
    }

    struct BlockingMathAdapter: MathRenderingAdapter {
        private let output: String
        private let state: BlockingResourceState

        init(output: String, blockOnRender: Int = 1) {
            self.output = output
            self.state = BlockingResourceState(blockOnRender: blockOnRender)
        }

        func render(
            from node: MathNode,
            theme: Theme,
            contextFont: Font?
        ) async -> NSAttributedString {
            await state.recordRender(source: node.equation)
            return NSAttributedString(string: output)
        }

        func renderSync(
            from node: MathNode,
            theme: Theme,
            contextFont: Font?
        ) -> NSAttributedString {
            NSAttributedString(string: output)
        }

        func waitUntilFirstRenderStarts() async -> Bool {
            await state.waitUntilRenderStarts(1)
        }

        func releaseFirstRender() async {
            await state.releaseBlockedRender()
        }

        func renderedEquations() async -> [String] {
            await state.renderedSources
        }

        func cacheFingerprint(into hasher: inout Hasher) {
            hasher.combine("BlockingMathAdapter")
            hasher.combine(output)
        }
    }

    private actor BlockingResourceState {
        private let blockOnRender: Int
        private(set) var renderedSources: [String] = []
        private var isBlockedRenderReleased = false
        private var blockedRenderContinuation: CheckedContinuation<Void, Never>?

        init(blockOnRender: Int) {
            precondition(blockOnRender > 0)
            self.blockOnRender = blockOnRender
        }

        var renderCount: Int {
            renderedSources.count
        }

        func recordRender(source: String) async {
            renderedSources.append(source)
            if renderedSources.count == blockOnRender, !isBlockedRenderReleased {
                await withCheckedContinuation { continuation in
                    blockedRenderContinuation = continuation
                }
            }
        }

        func waitUntilRenderStarts(_ renderNumber: Int) async -> Bool {
            for _ in 0..<200 {
                if renderedSources.count >= renderNumber {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return renderedSources.count >= renderNumber
        }

        func waitUntilBlockedRenderStarts() async -> Bool {
            await waitUntilRenderStarts(blockOnRender)
        }

        func releaseBlockedRender() {
            isBlockedRenderReleased = true
            blockedRenderContinuation?.resume()
            blockedRenderContinuation = nil
        }
    }
}

private enum TestFixtureError: Error {
    case invalidPNGData
}
