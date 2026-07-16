import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class AsyncImageViewLoadingTests: XCTestCase {

    private var testImageURL: URL!

    override func setUp() {
        super.setUp()
        // Generate a small 10x10 red PNG for testing without network dependency
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let data = renderer.pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        testImageURL = FileManager.default.temporaryDirectory.appendingPathComponent("mktest_\(UUID().uuidString).png")
        try? data.write(to: testImageURL)
    }

    override func tearDown() {
        if let url = testImageURL {
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func waitForLayerContents(_ view: UIView, timeout: TimeInterval = 3.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while view.layer.contents == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Tests

    func testImageLoadingFromLocalFile() async throws {
        let node = ImageNode(range: nil, source: testImageURL.absoluteString, altText: "red square", title: nil)
        let layout = LayoutResult(node: node, size: CGSize(width: 10, height: 10))

        let view = AsyncImageView(frame: CGRect(origin: .zero, size: layout.size))
        view.configure(with: layout, imageLoadingPolicy: .trusted)

        try await waitForLayerContents(view)
        XCTAssertNotNil(view.layer.contents, "Local image should load and decode into layer.contents")
    }

    func testImageLoadingFromRelativeLocalPath() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let fixtureDir = cwd.appendingPathComponent(".build/async-image-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)

        let fixtureURL = fixtureDir.appendingPathComponent("relative-\(UUID().uuidString).png")
        let data = try Data(contentsOf: testImageURL)
        try data.write(to: fixtureURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let relativePath = fixtureURL.path.replacingOccurrences(
            of: cwd.path + "/",
            with: ""
        )
        let node = ImageNode(range: nil, source: relativePath, altText: "relative", title: nil)
        let layout = LayoutResult(node: node, size: CGSize(width: 10, height: 10))

        let view = AsyncImageView(frame: CGRect(origin: .zero, size: layout.size))
        view.configure(with: layout, imageLoadingPolicy: .trusted)

        try await waitForLayerContents(view)
        XCTAssertNotNil(view.layer.contents, "Relative local image path should resolve and render")
    }

    func testImageLoadingCancelsOnReconfigure() async throws {
        let nodeA = ImageNode(range: nil, source: testImageURL.absoluteString, altText: "A", title: nil)
        let layoutA = LayoutResult(node: nodeA, size: CGSize(width: 10, height: 10))

        // Create a second fixture image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 5, height: 5))
        let data = renderer.pngData { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 5, height: 5))
        }
        let urlB = FileManager.default.temporaryDirectory.appendingPathComponent("mktest_b_\(UUID().uuidString).png")
        try data.write(to: urlB)
        defer { try? FileManager.default.removeItem(at: urlB) }

        let nodeB = ImageNode(range: nil, source: urlB.absoluteString, altText: "B", title: nil)
        let layoutB = LayoutResult(node: nodeB, size: CGSize(width: 5, height: 5))

        let view = AsyncImageView(frame: .zero)
        // Configure with A, immediately reconfigure with B
        view.configure(with: layoutA, imageLoadingPolicy: .trusted)
        view.configure(with: layoutB, imageLoadingPolicy: .trusted)

        try await waitForLayerContents(view)
        // Should complete without crash
        XCTAssertNotNil(view.layer.contents)
    }

    func testConfigureClearsLayerBeforeUncachedLoad() async throws {
        let node = ImageNode(range: nil, source: testImageURL.absoluteString, altText: nil, title: nil)
        let layout = LayoutResult(node: node, size: CGSize(width: 10, height: 10))
        let uncachedLayout = LayoutResult(node: node, size: CGSize(width: 12, height: 12))

        let view = AsyncImageView(frame: CGRect(origin: .zero, size: layout.size))

        // First load
        view.configure(with: layout, imageLoadingPolicy: .trusted)
        try await waitForLayerContents(view)
        XCTAssertNotNil(view.layer.contents)

        // Reconfigure to a different size so the imageCache key is guaranteed uncached.
        // The stale layer.contents should still clear synchronously before the async load starts.
        view.configure(with: uncachedLayout, imageLoadingPolicy: .trusted)
        // The clearing (self.layer.contents = nil) happens before async task starts
        XCTAssertNil(view.layer.contents, "Reconfigure should synchronously clear layer.contents before starting new load")
        view.prepareForReuse()
    }

    func testDefaultPolicyDoesNotLoadLocalFiles() async throws {
        let node = ImageNode(range: nil, source: testImageURL.absoluteString, altText: "red square", title: nil)
        let layout = LayoutResult(node: node, size: CGSize(width: 10, height: 10))
        let resolved = try XCTUnwrap(ImageSourceResolver.resolve(testImageURL.absoluteString))

        XCTAssertTrue(ImageLoadingPolicy.default.allowedRemoteSchemes.isEmpty)
        XCTAssertFalse(ImageLoadingPolicy.default.allowsLocalFileURLs)
        XCTAssertFalse(ImageLoadingPolicy.default.allowsRelativeFilePaths)
        XCTAssertFalse(ImageLoadingPolicy.default.allows(resolved))

        let view = AsyncImageView(frame: CGRect(origin: .zero, size: layout.size))
        view.configure(with: layout)

        XCTAssertNil(view.layer.contents, "Default image loading policy must not perform local image I/O")
        await Task.yield()
        XCTAssertNil(view.layer.contents, "Default policy should continue to block local image loading")
    }

    func testContentsGravityIsResizeAspect() {
        let view = AsyncImageView(frame: .zero)
        XCTAssertEqual(view.layer.contentsGravity, .resizeAspect)
    }
}
#endif
