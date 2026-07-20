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
        private let state = BlockingDiagramAdapterState()

        init(output: String) {
            self.output = output
        }

        func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
            await state.recordRender(source: source)
            return NSAttributedString(string: output)
        }

        func waitUntilFirstRenderStarts() async -> Bool {
            await state.waitUntilFirstRenderStarts()
        }

        func releaseFirstRender() async {
            await state.releaseFirstRender()
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

    private actor BlockingDiagramAdapterState {
        private(set) var renderedSources: [String] = []
        private var isFirstRenderReleased = false
        private var firstRenderContinuation: CheckedContinuation<Void, Never>?

        var renderCount: Int {
            renderedSources.count
        }

        func recordRender(source: String) async {
            renderedSources.append(source)
            if renderedSources.count == 1, !isFirstRenderReleased {
                await withCheckedContinuation { continuation in
                    firstRenderContinuation = continuation
                }
            }
        }

        func waitUntilFirstRenderStarts() async -> Bool {
            for _ in 0..<200 {
                if !renderedSources.isEmpty {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return !renderedSources.isEmpty
        }

        func releaseFirstRender() {
            isFirstRenderReleased = true
            firstRenderContinuation?.resume()
            firstRenderContinuation = nil
        }
    }
}

private enum TestFixtureError: Error {
    case invalidPNGData
}
