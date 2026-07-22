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
/// That diagnostics state (and its lock) only exists in DEBUG builds; Release builds
/// carry no additional mutable state beyond the thread-safe `NSCache`.
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
#if DEBUG
                sharedCache.recordLookup(hit: true)
#endif
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

    private static let defaultTotalCostLimit = 64 * 1_024 * 1_024

    private let cache: NSCache<CacheKey, LayoutResultWrapper>
    private let configuredTotalCostLimit: Int

    // MARK: - Test diagnostics (do not use in production paths)
    //
    // The hit/miss counters (and their lock) exist only in DEBUG builds. Release
    // builds compile out this state entirely and every lookup call site along
    // with it, so the accessors below simply report zero and `resetStatsForTesting()`
    // is a no-op — they still exist so Release-compiled test sources link and run.

#if DEBUG
    private let statsLock = NSLock()
    private var hitCountStorage: Int = 0
    private var missCountStorage: Int = 0
#endif

    var hitCountForTesting: Int {
#if DEBUG
        statsLock.lock()
        defer { statsLock.unlock() }
        return hitCountStorage
#else
        return 0
#endif
    }

    var missCountForTesting: Int {
#if DEBUG
        statsLock.lock()
        defer { statsLock.unlock() }
        return missCountStorage
#else
        return 0
#endif
    }

    var countLimitForTesting: Int {
        cache.countLimit
    }

    var totalCostLimitForTesting: Int {
        configuredTotalCostLimit
    }

    func resetStatsForTesting() {
#if DEBUG
        statsLock.lock()
        hitCountStorage = 0
        missCountStorage = 0
        statsLock.unlock()
#endif
    }

    // NSCache requires class objects, so we wrap the struct LayoutResult
    private class LayoutResultWrapper {
        let result: LayoutResult
        init(_ result: LayoutResult) {
            self.result = result
        }
    }

    public init(countLimit: Int = 100_000) {
        configuredTotalCostLimit = Self.defaultTotalCostLimit
        cache = Self.makeCache(
            countLimit: countLimit,
            totalCostLimit: configuredTotalCostLimit
        )
    }

    init(countLimit: Int, totalCostLimit: Int) {
        configuredTotalCostLimit = max(0, totalCostLimit)
        cache = Self.makeCache(
            countLimit: countLimit,
            totalCostLimit: configuredTotalCostLimit
        )
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
#if DEBUG
        recordLookup(hit: result != nil)
#endif
        return result
    }

    private func setLayout(_ result: LayoutResult, for key: Key) {
        let cost = result.estimatedCacheCost
        guard configuredTotalCostLimit == 0 || cost <= configuredTotalCostLimit else { return }

        let wrapper = LayoutResultWrapper(result)
        cache.setObject(wrapper, forKey: CacheKey(key), cost: cost)
    }

    private static func makeCache(
        countLimit: Int,
        totalCostLimit: Int
    ) -> NSCache<CacheKey, LayoutResultWrapper> {
        let cache = NSCache<CacheKey, LayoutResultWrapper>()
        // NSCache count and cost limits are advisory pressure hints, not strict
        // LRU bounds or guarantees about process resident memory.
        cache.countLimit = max(0, countLimit)
        cache.totalCostLimit = max(0, totalCostLimit)
        return cache
    }

#if DEBUG
    private func recordLookup(hit: Bool) {
        statsLock.lock()
        if hit {
            hitCountStorage += 1
        } else {
            missCountStorage += 1
        }
        statsLock.unlock()
    }
#endif

    /// Clears all stored layouts (e.g. upon memory warning).
    public func clear() {
        cache.removeAllObjects()
    }
}
