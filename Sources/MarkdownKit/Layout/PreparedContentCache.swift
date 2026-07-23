//
//  PreparedContentCache.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Strict-cost LRU cache for width-independent prepared attributed content.
///
/// Keyed by `(contentHash, interactionHash?, variantHash, localeIdentifier)` —
/// no layout width.
/// Eviction is strict and deterministic: LRU entries are removed whenever the
/// entry-count limit or the byte-cost limit would be exceeded after an insertion.
/// All operations, including retained-cost estimation, are O(1) amortised.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
final class PreparedContentCache: @unchecked Sendable {

    // MARK: - Key

    struct Key: Hashable {
        let contentHash: Int
        let interactionHash: Int?
        let variantHash: Int
        let localeIdentifier: String

        init(
            contentHash: Int,
            interactionHash: Int?,
            variantHash: Int,
            localeIdentifier: String = Locale.current.identifier
        ) {
            self.contentHash = contentHash
            self.interactionHash = interactionHash
            self.variantHash = variantHash
            self.localeIdentifier = localeIdentifier
        }

        init(
            node: MarkdownNode,
            variantHash: Int,
            localeIdentifier: String = Locale.current.identifier
        ) {
            self.init(
                contentHash: node.contentFingerprint,
                interactionHash: node._interactionFingerprint,
                variantHash: variantHash,
                localeIdentifier: localeIdentifier
            )
        }
    }

    // MARK: - Payload

    enum MeasurementPlan {
        case textKit
        case arithmetic(ArithmeticTextCalculator.PreparedText)
        case codeBlockInset
    }

    /// Immutable content payload. `attributedString` is frozen at init via `copy()`.
    ///
    /// `@unchecked Sendable`: `NSAttributedString` is read-only after `copy()`; the
    /// `PreparedText` arrays are constructed once and never mutated after storage.
    struct Payload: @unchecked Sendable {
        let attributedString: NSAttributedString
        let measurementPlan: MeasurementPlan

        init(attributedString: NSAttributedString, measurementPlan: MeasurementPlan) {
            self.attributedString = NSAttributedString(attributedString: attributedString)
            self.measurementPlan = measurementPlan
        }
    }

    // MARK: - Write batch

    struct WriteBatch {
        private struct Entry {
            let key: Key
            var payload: Payload
        }

        private let sharedCache: PreparedContentCache
        private var entries: [Entry] = []
        private var entryIndexByKey: [Key: Int] = [:]

        fileprivate init(sharedCache: PreparedContentCache) {
            self.sharedCache = sharedCache
        }

        func get(_ key: Key) -> Payload? {
            if let index = entryIndexByKey[key] {
                sharedCache.recordLookup(hit: true)
                return entries[index].payload
            }
            return sharedCache.get(key)
        }

        mutating func stage(_ payload: Payload, for key: Key) {
            if let index = entryIndexByKey[key] {
                entries[index].payload = payload
                return
            }
            entryIndexByKey[key] = entries.count
            entries.append(Entry(key: key, payload: payload))
        }

        func commit() {
            for entry in entries {
                sharedCache.set(entry.payload, for: entry.key)
            }
        }
    }

    // MARK: - Limits (immutable after init)

    let maxEntryCount: Int
    let maxCostBytes: Int

    // MARK: - LRU list node

    private final class Entry {
        let key: Key?
        let payload: Payload?
        let estimatedCost: Int
        weak var prev: Entry?   // weak to break the head ↔ tail sentinel cycle
        var next: Entry?

        init(key: Key, payload: Payload, estimatedCost: Int) {
            self.key = key
            self.payload = payload
            self.estimatedCost = estimatedCost
        }

        // Sentinel nodes carry no data.
        init() {
            key = nil
            payload = nil
            estimatedCost = 0
        }
    }

    // MARK: - Storage (all mutable fields guarded by lock)

    // Invariant: head.next → MRU … LRU → tail.prev
    private let head = Entry()
    private let tail = Entry()
    private let lock = NSLock()
    private var storage: [Key: Entry] = [:]
    private var _entryCount: Int = 0
    private var _totalCost: Int = 0
    private var _hitCount: Int = 0
    private var _missCount: Int = 0

    // MARK: - Init

    init(maxEntryCount: Int = 2_048, maxCostBytes: Int = 32 * 1_024 * 1_024) {
        self.maxEntryCount = max(0, maxEntryCount)
        self.maxCostBytes = max(0, maxCostBytes)
        head.next = tail
        tail.prev = head
    }

    // MARK: - Cache API

    /// Returns the payload for `key`, promoting it to MRU position, or `nil` on miss.
    func get(_ key: Key) -> Payload? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else {
            _missCount += 1
            return nil
        }
        _hitCount += 1
        promote(entry)
        return entry.payload
    }

    /// Stores `payload` under `key`, replacing any existing entry with exact accounting.
    /// Entries whose estimated cost exceeds `maxCostBytes`, or any entry when either
    /// limit is zero, are silently discarded without evicting existing entries.
    func set(_ payload: Payload, for key: Key) {
        let cost = Self.estimateCost(for: payload)
        lock.lock()
        defer { lock.unlock() }
        guard maxEntryCount > 0, maxCostBytes > 0, cost <= maxCostBytes else { return }
        if let existing = storage[key] { removeEntry(existing) }
        let entry = Entry(key: key, payload: payload, estimatedCost: cost)
        storage[key] = entry
        insertAtHead(entry)
        _entryCount += 1
        _totalCost = Self.saturatingAdd(_totalCost, cost)
        evictIfNeeded()
    }

    func makeWriteBatch() -> WriteBatch {
        WriteBatch(sharedCache: self)
    }

    /// Removes all entries and resets cost/count accounting.
    /// Hit and miss diagnostic counters are not reset.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        head.next = tail
        tail.prev = head
        _entryCount = 0
        _totalCost = 0
    }

    // MARK: - Test diagnostics (internal; accessible via @testable)

    var entryCountForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return _entryCount
    }

    var totalRetainedCostForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return _totalCost
    }

    var hitCountForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return _hitCount
    }

    var missCountForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return _missCount
    }

    func resetDiagnosticsForTesting() {
        lock.lock()
        defer { lock.unlock() }
        _hitCount = 0
        _missCount = 0
    }

    func containsForTesting(_ key: Key) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage[key] != nil
    }

    static func estimateCostForTesting(_ payload: Payload) -> Int {
        estimateCost(for: payload)
    }

    // MARK: - Private helpers (all called while lock is held)

    private func promote(_ entry: Entry) {
        removeFromList(entry)
        insertAtHead(entry)
    }

    private func insertAtHead(_ entry: Entry) {
        let successor = head.next
        entry.prev = head
        entry.next = successor
        successor?.prev = entry
        head.next = entry
    }

    private func removeFromList(_ entry: Entry) {
        entry.prev?.next = entry.next
        entry.next?.prev = entry.prev
        entry.prev = nil
        entry.next = nil
    }

    private func removeEntry(_ entry: Entry) {
        guard let key = entry.key else { return }
        storage.removeValue(forKey: key)
        removeFromList(entry)
        _entryCount -= 1
        _totalCost = max(0, _totalCost - entry.estimatedCost)
    }

    private func evictIfNeeded() {
        while _entryCount > maxEntryCount || _totalCost > maxCostBytes {
            guard let lru = tail.prev, lru !== head else { break }
            removeEntry(lru)
        }
    }

    // MARK: - Cost estimation

    /// Deterministic byte estimate for `payload`. Never enumerates attributed runs.
    /// Always positive: a fixed entry overhead plus proportional string, segment, and paragraph storage.
    private static func estimateCost(for payload: Payload) -> Int {
        // Conservatively cover character storage plus fonts, colors, paragraph
        // styles, and highlighted attribute-run overhead without enumerating runs.
        let base = saturatingAdd(256, saturatingMul(payload.attributedString.length, 64))
        guard case .arithmetic(let pt) = payload.measurementPlan else { return base }

        var preparedCost = 0
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.widths.count, MemoryLayout<CGFloat>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.kinds.count, MemoryLayout<ArithmeticTextCalculator.SegmentKind>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.lineEndFitAdvances.count, MemoryLayout<CGFloat>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.lineEndPaintAdvances.count, MemoryLayout<CGFloat>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.segmentTexts.count, MemoryLayout<String>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.ctFonts.count, MemoryLayout<CTFont?>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.heights.count, MemoryLayout<CGFloat>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.chunks.count, MemoryLayout<ArithmeticTextCalculator.Chunk>.stride)
        )
        preparedCost = saturatingAdd(
            preparedCost,
            saturatingMul(pt.paragraphs.count, MemoryLayout<ArithmeticTextCalculator.Paragraph>.stride)
        )
        return saturatingAdd(base, preparedCost)
    }

    private func recordLookup(hit: Bool) {
        lock.lock()
        if hit {
            _hitCount += 1
        } else {
            _missCount += 1
        }
        lock.unlock()
    }

    private static func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (v, overflow) = a.addingReportingOverflow(b)
        return overflow ? .max : v
    }

    private static func saturatingMul(_ a: Int, _ b: Int) -> Int {
        let (v, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? .max : v
    }
}
