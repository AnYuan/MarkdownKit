import XCTest
import ImageIO
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class ImageAttachmentBuilderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ImageAttachmentBuilder.clearCache()
    }

    override func tearDown() {
        ImageAttachmentBuilder.clearCache()
        super.tearDown()
    }

    func testLargeTrustedImageCreatesBoundedAttachment() async throws {
        let fixture = try makeFixtureImage(width: 2_400, height: 1_200)
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let attachment = try await buildAttachment(source: fixture.url.absoluteString, width: 400)
        let bounds = attachment.bounds
        let decodedImage = try XCTUnwrap(cgImage(from: attachment))

        XCTAssertTrue(bounds.width.isFinite && bounds.height.isFinite)
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
        XCTAssertEqual(bounds.width / bounds.height, 2, accuracy: 0.001)
        XCTAssertLessThan(decodedImage.width, fixture.width / 2)
        XCTAssertLessThanOrEqual(CGFloat(decodedImage.width), ceil(bounds.width))
        XCTAssertLessThanOrEqual(CGFloat(decodedImage.height), ceil(bounds.height))
    }

    func testSameSourcePolicyAndWidthUsesDecodedCache() async throws {
        let fixture = try makeFixtureImage()
        let source = fixture.url.absoluteString
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        _ = try await buildAttachment(source: source, width: 400)
        try FileManager.default.removeItem(at: fixture.url)

        _ = try await buildAttachment(source: source, width: 400)
    }

    func testDifferentWidthCannotUseCachedThumbnail() async throws {
        let fixture = try makeFixtureImage()
        let source = fixture.url.absoluteString
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        _ = try await buildAttachment(source: source, width: 400)
        try FileManager.default.removeItem(at: fixture.url)

        let node = ImageNode(range: nil, source: source, altText: "fixture", title: nil)
        let result = await ImageAttachmentBuilder.build(
            from: node,
            constrainedToWidth: 800,
            imageLoadingPolicy: .trusted
        )
        XCTAssertNil(result)
    }

    func testDifferentPolicyCannotUseTrustedCachedImage() async throws {
        let fixture = try makeFixtureImage()
        let source = fixture.url.absoluteString
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        _ = try await buildAttachment(source: source, width: 400)
        try FileManager.default.removeItem(at: fixture.url)

        let node = ImageNode(range: nil, source: source, altText: "fixture", title: nil)
        let result = await ImageAttachmentBuilder.build(
            from: node,
            constrainedToWidth: 400,
            imageLoadingPolicy: .default
        )
        XCTAssertNil(result)
    }

    func testClearCacheRemovesDecodedAttachment() async throws {
        let fixture = try makeFixtureImage()
        let source = fixture.url.absoluteString
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        _ = try await buildAttachment(source: source, width: 400)
        try FileManager.default.removeItem(at: fixture.url)
        ImageAttachmentBuilder.clearCache()

        let node = ImageNode(range: nil, source: source, altText: "fixture", title: nil)
        let result = await ImageAttachmentBuilder.build(
            from: node,
            constrainedToWidth: 400,
            imageLoadingPolicy: .trusted
        )
        XCTAssertNil(result)
    }

    private func buildAttachment(source: String, width: CGFloat) async throws -> NSTextAttachment {
        let node = ImageNode(range: nil, source: source, altText: "fixture", title: nil)
        let built = await ImageAttachmentBuilder.build(
            from: node,
            constrainedToWidth: width,
            imageLoadingPolicy: .trusted
        )
        let result = try XCTUnwrap(built)
        return try XCTUnwrap(
            result.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
    }

    private func makeFixtureImage(
        width: Int = 2_400,
        height: Int = 1_200
    ) throws -> (url: URL, width: Int, height: Int) {
        let fixtureDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/image-attachment-builder-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        let url = fixtureDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ImageAttachmentBuilderTests", code: 1)
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  "public.png" as CFString,
                  1,
                  nil
              ) else {
            throw NSError(domain: "ImageAttachmentBuilderTests", code: 2)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageAttachmentBuilderTests", code: 3)
        }
        return (url, width, height)
    }

    private func cgImage(from attachment: NSTextAttachment) -> CGImage? {
        #if canImport(UIKit)
        attachment.image?.cgImage
        #elseif canImport(AppKit)
        guard let image = attachment.image else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }
}
