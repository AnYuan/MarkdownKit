//
//  LayoutCache.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A thread-safe cache storing previously computed layout results.
/// The cache is keyed on a **content fingerprint** of the node rather than its UUID.
/// This enables cache hits during streaming scenarios where each call to `parser.parse()`
/// creates fresh AST nodes with new UUIDs, but unchanged paragraphs produce identical content.
///
/// `@unchecked Sendable` because the internal storage (`NSCache`) is thread-safe and
/// the only mutable state (`hitCountStorage` / `missCountStorage`) is guarded by `statsLock`.
public final class LayoutCache: @unchecked Sendable {

    // MARK: - Cache Key

    /// The internal key structure for NSCache, based on content fingerprint + width.
    private class CacheKey: NSObject {
        let contentHash: Int
        let width: Int
        let variantHash: Int

        init(contentHash: Int, width: CGFloat, variantHash: Int) {
            self.contentHash = contentHash
            self.variantHash = variantHash
            // Hash and compare exact integer widths since floating point jitter
            // inside scroll views often breaks fuzzy hit rates.
            self.width = Int(width.rounded())
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(contentHash)
            hasher.combine(width)
            hasher.combine(variantHash)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return self.contentHash == other.contentHash
                && self.width == other.width
                && self.variantHash == other.variantHash
        }
    }

    // MARK: - Storage

    private let cache = NSCache<CacheKey, LayoutResultWrapper>()

    // MARK: - Test diagnostics (do not use in production paths)

    private let statsLock = NSLock()
    private var hitCountStorage: Int = 0
    private var missCountStorage: Int = 0

    public var hitCountForTesting: Int {
        statsLock.lock()
        defer { statsLock.unlock() }
        return hitCountStorage
    }

    public var missCountForTesting: Int {
        statsLock.lock()
        defer { statsLock.unlock() }
        return missCountStorage
    }

    public func resetStatsForTesting() {
        statsLock.lock()
        hitCountStorage = 0
        missCountStorage = 0
        statsLock.unlock()
    }

    // NSCache requires class objects, so we wrap the struct LayoutResult
    private class LayoutResultWrapper {
        let result: LayoutResult
        init(_ result: LayoutResult) {
            self.result = result
        }
    }

    public init(countLimit: Int = 100_000) {
        // Limit cache to prevent memory pressure on massive documents.
        // 100k layout models usually take single-digit megabytes since they are purely structs of CGRects.
        cache.countLimit = countLimit
    }

    // MARK: - Public API

    /// Retrieve a pre-calculated layout if it exists for the given node and container width.
    ///
    /// O(1) with respect to subtree size: `node.contentFingerprint` was computed
    /// once at parse time, so no recursive tree walk happens here.
    public func getLayout(
        for node: MarkdownNode,
        constrainedToWidth width: CGFloat,
        variantHash: Int = 0
    ) -> LayoutResult? {
        let key = CacheKey(
            contentHash: node.contentFingerprint,
            width: width,
            variantHash: variantHash
        )
        let result = cache.object(forKey: key)?.result
        statsLock.lock()
        if result != nil {
            hitCountStorage += 1
        } else {
            missCountStorage += 1
        }
        statsLock.unlock()
        return result
    }

    /// Store a freshly computed layout frame.
    public func setLayout(
        _ result: LayoutResult,
        constrainedToWidth width: CGFloat,
        variantHash: Int = 0
    ) {
        let key = CacheKey(
            contentHash: result.node.contentFingerprint,
            width: width,
            variantHash: variantHash
        )
        let wrapper = LayoutResultWrapper(result)
        cache.setObject(wrapper, forKey: key)
    }

    /// Clears all stored layouts (e.g. upon memory warning).
    public func clear() {
        cache.removeAllObjects()
    }
}
