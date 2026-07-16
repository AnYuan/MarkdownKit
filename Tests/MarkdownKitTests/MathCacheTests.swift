import XCTest
@testable import MarkdownKit

#if canImport(WebKit)

final class MathCacheTests: XCTestCase {

    /// First call has to pay for SVG generation + rasterization; second call
    /// for the *same* equation must come back from `DefaultMathRenderingAdapter`'s
    /// internal image cache. We verify by measuring elapsed time — a cache hit
    /// is orders of magnitude faster than the MathJax → SwiftDraw round-trip,
    /// so a generous threshold is reliable across machines.
    func testSecondRenderReturnsCachedImageQuickly() async throws {
        // Use a unique equation per run to ensure the first render is a true miss.
        let equation = "x^2 + \(UUID().uuidString.prefix(8))"
        let node = MathNode(range: nil, style: .inline, equation: String(equation))
        let adapter = DefaultMathRenderingAdapter()

        let firstStart = Date()
        let first = await adapter.render(from: node, theme: .default, contextFont: nil)
        let firstElapsed = Date().timeIntervalSince(firstStart)

        // If the runtime can't reach MathJax / SwiftDraw, render falls back to
        // the literal equation string instead of an attachment. Skip in that case.
        guard hasAttachment(first) else {
            throw XCTSkip("Math rasterization unavailable in this runtime environment")
        }

        let secondStart = Date()
        let second = await adapter.render(from: node, theme: .default, contextFont: nil)
        let secondElapsed = Date().timeIntervalSince(secondStart)

        XCTAssertTrue(hasAttachment(second), "Cache hit should also produce an attachment string")
        XCTAssertLessThan(
            secondElapsed,
            firstElapsed,
            "Cached render should be measurably faster (first=\(firstElapsed)s, second=\(secondElapsed)s)"
        )
    }

    /// Sync render path requires a prior async render to populate the SVG cache;
    /// it returns a fallback string otherwise. Verifies the cache wiring.
    func testSyncRenderUsesPriorAsyncCache() async throws {
        let equation = "y = \\sin(\(UUID().uuidString.prefix(8)))"
        let node = MathNode(range: nil, style: .inline, equation: String(equation))
        let adapter = DefaultMathRenderingAdapter()

        _ = await adapter.render(from: node, theme: .default, contextFont: nil)
        let sync = adapter.renderSync(from: node, theme: .default, contextFont: nil)

        // Either both succeed (real attachment) or both fall back to text;
        // mismatch would mean the cache wiring is broken.
        let asyncAgain = await adapter.render(from: node, theme: .default, contextFont: nil)
        XCTAssertEqual(
            hasAttachment(sync),
            hasAttachment(asyncAgain),
            "renderSync must reuse the async path's image cache"
        )
    }

    /// Regression for a platform contract bug: on UIKit, `UIImage.size` is
    /// get-only, so the rasterized math image's reported size must still end
    /// up matching the preprocessed SVG's logical point size via the
    /// attachment bounds (rather than failing to build, or silently
    /// reporting a zero/garbage size). Exercises both the async and sync
    /// render paths.
    func testRenderedImageAttachmentHasPositiveFiniteSize() async throws {
        let equation = "a^2 + b^2 = c^2 \(UUID().uuidString.prefix(8))"
        let node = MathNode(range: nil, style: .inline, equation: String(equation))
        let adapter = DefaultMathRenderingAdapter()

        let rendered = await adapter.render(from: node, theme: .default, contextFont: nil)
        guard let bounds = attachmentBounds(rendered) else {
            throw XCTSkip("Math rasterization unavailable in this runtime environment")
        }

        XCTAssertTrue(bounds.width.isFinite && bounds.width > 0, "Attachment width must be a positive, finite point size")
        XCTAssertTrue(bounds.height.isFinite && bounds.height > 0, "Attachment height must be a positive, finite point size")

        let synced = adapter.renderSync(from: node, theme: .default, contextFont: nil)
        let syncBounds = try XCTUnwrap(
            attachmentBounds(synced),
            "Sync path must reuse the image cached by the successful async render"
        )
        XCTAssertEqual(syncBounds.width, bounds.width, accuracy: 0.5, "Sync path must reuse the cached image with the same reported width")
        XCTAssertEqual(syncBounds.height, bounds.height, accuracy: 0.5, "Sync path must reuse the cached image with the same reported height")
    }

    private func attachmentBounds(_ attributed: NSAttributedString) -> CGRect? {
        var bounds: CGRect?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, _, stop in
            if let attachment = value as? NSTextAttachment {
                bounds = attachment.bounds
                stop.pointee = true
            }
        }
        return bounds
    }

    private func hasAttachment(_ attributed: NSAttributedString) -> Bool {
        var found = false
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

#endif
