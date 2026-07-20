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
/// The cache is keyed on a **content fingerprint** of the node rather than its UUID,
/// plus a range-sensitive interaction fingerprint only when the rendered payload needs one.
/// This enables cache hits during streaming scenarios where each call to `parser.parse()`
/// creates fresh AST nodes with new UUIDs, but unchanged paragraphs produce identical content.
///
/// `@unchecked Sendable` because the internal storage (`NSCache`) is thread-safe and
/// the only mutable state (`hitCountStorage` / `missCountStorage`) is guarded by `statsLock`.
public final class LayoutCache: @unchecked Sendable {

    // MARK: - Cache Key

    struct Key: Hashable {
        let contentHash: Int
        let interactionHash: Int?
        let width: Int
        let variantHash: Int

        init(
            contentHash: Int,
            interactionHash: Int?,
            width: CGFloat,
            variantHash: Int
        ) {
            self.contentHash = contentHash
            self.interactionHash = interactionHash
            self.width = Int(width.rounded())
            self.variantHash = variantHash
        }

        init(node: MarkdownNode, width: CGFloat, variantHash: Int) {
            self.init(
                contentHash: node.contentFingerprint,
                interactionHash: node._interactionFingerprint,
                width: width,
                variantHash: variantHash
            )
        }

        init(result: LayoutResult, width: CGFloat, variantHash: Int) {
            self.init(
                contentHash: result.node.contentFingerprint,
                interactionHash: result.interactionFingerprint,
                width: width,
                variantHash: variantHash
            )
        }
    }

    struct WriteBatch {
        private struct Entry {
            let key: Key
            var result: LayoutResult
        }

        private let sharedCache: LayoutCache
        private var entries: [Entry] = []
        private var entryIndexByKey: [Key: Int] = [:]

        fileprivate init(sharedCache: LayoutCache) {
            self.sharedCache = sharedCache
        }

        mutating func getLayout(
            for node: MarkdownNode,
            constrainedToWidth width: CGFloat,
            variantHash: Int
        ) -> LayoutResult? {
            let key = Key(node: node, width: width, variantHash: variantHash)
            if let index = entryIndexByKey[key] {
                sharedCache.recordLookup(hit: true)
                return entries[index].result
            }
            return sharedCache.getLayout(for: key)
        }

        mutating func stage(
            _ result: LayoutResult,
            constrainedToWidth width: CGFloat,
            variantHash: Int
        ) {
            let key = Key(result: result, width: width, variantHash: variantHash)
            if let index = entryIndexByKey[key] {
                entries[index].result = result
                return
            }
            entryIndexByKey[key] = entries.count
            entries.append(Entry(key: key, result: result))
        }

        /// Publishes staged child-before-parent entries after successful root completion.
        /// Dropping the batch before this point discards every staged write.
        func commit() {
            for entry in entries {
                sharedCache.setLayout(entry.result, for: entry.key)
            }
        }
    }

    /// The object key used by NSCache. Equality delegates to the canonical value key.
    private class CacheKey: NSObject {
        let key: Key

        init(_ key: Key) {
            self.key = key
        }

        override var hash: Int {
            key.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return key == other.key
        }
    }

    // MARK: - Storage

    private let cache = NSCache<CacheKey, LayoutResultWrapper>()

    // MARK: - Test diagnostics (do not use in production paths)

    private let statsLock = NSLock()
    private var hitCountStorage: Int = 0
    private var missCountStorage: Int = 0

    var hitCountForTesting: Int {
        statsLock.lock()
        defer { statsLock.unlock() }
        return hitCountStorage
    }

    var missCountForTesting: Int {
        statsLock.lock()
        defer { statsLock.unlock() }
        return missCountStorage
    }

    func resetStatsForTesting() {
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

    func makeWriteBatch() -> WriteBatch {
        WriteBatch(sharedCache: self)
    }

    // MARK: - Cache Operations

    /// Retrieve a pre-calculated layout if it exists for the given node and container width.
    ///
    /// O(1) with respect to subtree size: content and interaction fingerprints
    /// were computed once at parse time, so no recursive tree walk happens here.
    func getLayout(
        for node: MarkdownNode,
        constrainedToWidth width: CGFloat,
        variantHash: Int = 0
    ) -> LayoutResult? {
        getLayout(for: Key(node: node, width: width, variantHash: variantHash))
    }

    /// Store a freshly computed layout frame.
    func setLayout(
        _ result: LayoutResult,
        constrainedToWidth width: CGFloat,
        variantHash: Int = 0
    ) {
        let key = Key(result: result, width: width, variantHash: variantHash)
        setLayout(result, for: key)
    }

    private func getLayout(for key: Key) -> LayoutResult? {
        let result = cache.object(forKey: CacheKey(key))?.result
        recordLookup(hit: result != nil)
        return result
    }

    private func setLayout(_ result: LayoutResult, for key: Key) {
        let wrapper = LayoutResultWrapper(result)
        cache.setObject(wrapper, forKey: CacheKey(key))
    }

    private func recordLookup(hit: Bool) {
        statsLock.lock()
        if hit {
            hitCountStorage += 1
        } else {
            missCountStorage += 1
        }
        statsLock.unlock()
    }

    /// Clears all stored layouts (e.g. upon memory warning).
    public func clear() {
        cache.removeAllObjects()
    }
}
