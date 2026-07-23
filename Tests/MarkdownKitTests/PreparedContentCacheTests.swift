//
//  PreparedContentCacheTests.swift
//  MarkdownKit
//

import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class PreparedContentCacheTests: XCTestCase {

    private typealias Cache = PreparedContentCache
    private typealias Key = PreparedContentCache.Key
    private typealias Payload = PreparedContentCache.Payload
    private typealias Plan = PreparedContentCache.MeasurementPlan

    // MARK: - Helpers

    private func key(_ content: Int, interaction: Int? = nil, variant: Int = 0) -> Key {
        Key(contentHash: content, interactionHash: interaction, variantHash: variant)
    }

    private func payload(_ text: String, plan: Plan = .textKit) -> Payload {
        Payload(attributedString: NSAttributedString(string: text), measurementPlan: plan)
    }

    private func preparedText(segments: Int) -> ArithmeticTextCalculator.PreparedText {
        var pt = ArithmeticTextCalculator.PreparedText()
        for i in 0..<segments {
            pt.append(width: CGFloat(i + 1) * 8, kind: .text, height: 14, text: "w\(i)")
        }
        return pt
    }

    // MARK: - Key equality / distinction

    func testKeyEqualWhenAllFieldsMatch() {
        XCTAssertEqual(
            Key(contentHash: 42, interactionHash: 7, variantHash: 3),
            Key(contentHash: 42, interactionHash: 7, variantHash: 3)
        )
    }

    func testKeyEqualNilAndNilInteractionHash() {
        XCTAssertEqual(
            Key(contentHash: 1, interactionHash: nil, variantHash: 0),
            Key(contentHash: 1, interactionHash: nil, variantHash: 0)
        )
    }

    func testKeyDistinctOnContentHash() {
        XCTAssertNotEqual(
            Key(contentHash: 1, interactionHash: nil, variantHash: 0),
            Key(contentHash: 2, interactionHash: nil, variantHash: 0)
        )
    }

    func testKeyDistinctOnInteractionHash() {
        XCTAssertNotEqual(
            Key(contentHash: 1, interactionHash: nil, variantHash: 0),
            Key(contentHash: 1, interactionHash: 1, variantHash: 0)
        )
        XCTAssertNotEqual(
            Key(contentHash: 1, interactionHash: 10, variantHash: 0),
            Key(contentHash: 1, interactionHash: 20, variantHash: 0)
        )
    }

    func testKeyDistinctOnVariantHash() {
        XCTAssertNotEqual(
            Key(contentHash: 1, interactionHash: nil, variantHash: 0),
            Key(contentHash: 1, interactionHash: nil, variantHash: 1)
        )
    }

    func testKeyDistinctOnLocaleIdentifier() {
        XCTAssertNotEqual(
            Key(
                contentHash: 1,
                interactionHash: nil,
                variantHash: 0,
                localeIdentifier: "en_US"
            ),
            Key(
                contentHash: 1,
                interactionHash: nil,
                variantHash: 0,
                localeIdentifier: "th_TH"
            )
        )
    }

    // MARK: - No width dimension

    func testKeyHasNoWidthDimension() {
        // The same content+variant key must always hit regardless of any layout-width context.
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let stored = key(99, variant: 3)
        cache.set(payload("hello"), for: stored)
        let sameKey = Key(contentHash: 99, interactionHash: nil, variantHash: 3)
        XCTAssertEqual(stored, sameKey)
        XCTAssertNotNil(cache.get(sameKey),
            "PreparedContentCache.Key has no width dimension; same fields must always hit")
    }

    // MARK: - Frozen-copy safety

    func testPayloadFreezesMutableAttributedString() {
        let mutable = NSMutableAttributedString(string: "original")
        let p = Payload(attributedString: mutable, measurementPlan: .textKit)
        mutable.mutableString.setString("mutated")
        XCTAssertEqual(p.attributedString.string, "original",
            "Payload must store a frozen copy independent of the mutable source")
    }

    func testCachedPayloadUnaffectedBySourceMutation() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let mutable = NSMutableAttributedString(string: "before")
        let p = Payload(attributedString: mutable, measurementPlan: .textKit)
        cache.set(p, for: key(1))
        mutable.mutableString.setString("after")
        XCTAssertEqual(cache.get(key(1))?.attributedString.string, "before")
    }

    // MARK: - Hit / miss diagnostics

    func testMissOnEmptyCache() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        XCTAssertNil(cache.get(key(1)))
        XCTAssertEqual(cache.missCountForTesting, 1)
        XCTAssertEqual(cache.hitCountForTesting, 0)
    }

    func testHitAfterSet() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let k = key(1)
        cache.set(payload("hi"), for: k)
        XCTAssertNotNil(cache.get(k))
        XCTAssertEqual(cache.hitCountForTesting, 1)
        XCTAssertEqual(cache.missCountForTesting, 0)
    }

    func testMissAndHitAccumulateIndependently() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        _ = cache.get(key(99))          // miss
        _ = cache.get(key(100))         // miss
        cache.set(payload("x"), for: key(1))
        _ = cache.get(key(1))           // hit
        XCTAssertEqual(cache.missCountForTesting, 2)
        XCTAssertEqual(cache.hitCountForTesting, 1)
    }

    func testResetDiagnosticsZeroesCounters() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        _ = cache.get(key(1))
        cache.set(payload("a"), for: key(2))
        _ = cache.get(key(2))
        cache.resetDiagnosticsForTesting()
        XCTAssertEqual(cache.hitCountForTesting, 0)
        XCTAssertEqual(cache.missCountForTesting, 0)
    }

    // MARK: - Write batch

    func testWriteBatchStagedLookupRecordsHit() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        var batch = cache.makeWriteBatch()
        let stagedKey = key(1)

        batch.stage(payload("staged"), for: stagedKey)

        XCTAssertEqual(batch.get(stagedKey)?.attributedString.string, "staged")
        XCTAssertEqual(cache.hitCountForTesting, 1)
        XCTAssertEqual(cache.missCountForTesting, 0)
        XCTAssertEqual(cache.entryCountForTesting, 0)
    }

    func testWriteBatchSharedFallbackRecordsHitAndMiss() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let hitKey = key(1)
        let missKey = key(2)
        cache.set(payload("shared"), for: hitKey)

        let batch = cache.makeWriteBatch()

        XCTAssertEqual(batch.get(hitKey)?.attributedString.string, "shared")
        XCTAssertNil(batch.get(missKey))
        XCTAssertEqual(cache.hitCountForTesting, 1)
        XCTAssertEqual(cache.missCountForTesting, 1)
    }

    func testWriteBatchDuplicateReplacementKeepsLatestPayload() {
        let cache = Cache(maxEntryCount: 2, maxCostBytes: Int.max)
        let duplicateKey = key(1)
        let newerKey = key(2)
        let overflowKey = key(3)
        var batch = cache.makeWriteBatch()

        batch.stage(payload("v1"), for: duplicateKey)
        batch.stage(payload("v2"), for: newerKey)
        batch.stage(payload("v1b"), for: duplicateKey)

        XCTAssertEqual(batch.get(duplicateKey)?.attributedString.string, "v1b")

        batch.commit()
        cache.set(payload("overflow"), for: overflowKey)

        XCTAssertFalse(cache.containsForTesting(duplicateKey))
        XCTAssertTrue(cache.containsForTesting(newerKey))
        XCTAssertTrue(cache.containsForTesting(overflowKey))
    }

    func testWriteBatchCommitPublishesStagedEntries() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let firstKey = key(1)
        let secondKey = key(2)
        var batch = cache.makeWriteBatch()

        batch.stage(payload("first"), for: firstKey)
        batch.stage(payload("second"), for: secondKey)
        batch.commit()

        XCTAssertEqual(cache.entryCountForTesting, 2)
        XCTAssertEqual(cache.get(firstKey)?.attributedString.string, "first")
        XCTAssertEqual(cache.get(secondKey)?.attributedString.string, "second")
    }

    func testWriteBatchDroppingBatchPublishesNothing() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let stagedKey = key(1)

        do {
            var batch = cache.makeWriteBatch()
            batch.stage(payload("abandoned"), for: stagedKey)
        }

        XCTAssertEqual(cache.entryCountForTesting, 0)
        XCTAssertFalse(cache.containsForTesting(stagedKey))
    }

    func testWriteBatchCommitPreservesInsertionOrderForLRU() {
        let cache = Cache(maxEntryCount: 2, maxCostBytes: Int.max)
        let oldestKey = key(1)
        let newerKey = key(2)
        let overflowKey = key(3)
        var batch = cache.makeWriteBatch()

        batch.stage(payload("oldest"), for: oldestKey)
        batch.stage(payload("newer"), for: newerKey)
        batch.commit()

        cache.set(payload("overflow"), for: overflowKey)

        XCTAssertFalse(cache.containsForTesting(oldestKey))
        XCTAssertTrue(cache.containsForTesting(newerKey))
        XCTAssertTrue(cache.containsForTesting(overflowKey))
    }

    // MARK: - MRU promotion

    func testGetPromotesToMRUPreventingEviction() {
        let cache = Cache(maxEntryCount: 2, maxCostBytes: Int.max)
        let k1 = key(1), k2 = key(2), k3 = key(3)

        cache.set(payload("a"), for: k1)  // will be LRU once k2 is inserted
        cache.set(payload("b"), for: k2)  // MRU; k1 is LRU

        _ = cache.get(k1)  // promote k1 to MRU; k2 becomes LRU

        cache.set(payload("c"), for: k3)  // count exceeds limit → evict LRU (k2, not k1)

        XCTAssertTrue(cache.containsForTesting(k1),  "k1 was promoted; must survive eviction")
        XCTAssertFalse(cache.containsForTesting(k2), "k2 is LRU after promotion; must be evicted")
        XCTAssertTrue(cache.containsForTesting(k3))
    }

    // MARK: - Strict count eviction

    func testStrictCountEviction() {
        let cache = Cache(maxEntryCount: 2, maxCostBytes: Int.max)
        let k1 = key(1), k2 = key(2), k3 = key(3)

        cache.set(payload("a"), for: k1)
        cache.set(payload("b"), for: k2)
        cache.set(payload("c"), for: k3)  // k1 is LRU → evicted

        XCTAssertEqual(cache.entryCountForTesting, 2)
        XCTAssertFalse(cache.containsForTesting(k1), "LRU entry must be evicted at count limit")
        XCTAssertTrue(cache.containsForTesting(k2))
        XCTAssertTrue(cache.containsForTesting(k3))
    }

    func testEntryCountNeverExceedsLimit() {
        let limit = 4
        let cache = Cache(maxEntryCount: limit, maxCostBytes: Int.max)
        for i in 0..<20 {
            cache.set(payload("entry\(i)"), for: key(i))
        }
        XCTAssertLessThanOrEqual(cache.entryCountForTesting, limit)
    }

    // MARK: - Strict cost eviction

    func testStrictCostEviction() {
        let p1 = payload("x")
        let p2 = payload("y")
        let singleCost = Cache.estimateCostForTesting(p1)
        // Limit is just below the combined cost of two equal-sized entries.
        let cache = Cache(maxEntryCount: 100, maxCostBytes: singleCost * 2 - 1)
        let k1 = key(1), k2 = key(2)

        cache.set(p1, for: k1)
        XCTAssertEqual(cache.entryCountForTesting, 1)

        cache.set(p2, for: k2)  // combined cost exceeds limit → k1 (LRU) evicted
        XCTAssertEqual(cache.entryCountForTesting, 1)
        XCTAssertFalse(cache.containsForTesting(k1), "LRU entry must be evicted to satisfy cost limit")
        XCTAssertTrue(cache.containsForTesting(k2))
        XCTAssertLessThanOrEqual(cache.totalRetainedCostForTesting, singleCost * 2 - 1)
    }

    func testTotalCostNeverExceedsLimit() {
        let limit = 800
        let cache = Cache(maxEntryCount: 100, maxCostBytes: limit)
        for i in 0..<30 {
            cache.set(payload("item \(i)"), for: key(i))
        }
        XCTAssertLessThanOrEqual(cache.totalRetainedCostForTesting, limit)
    }

    // MARK: - Oversized non-retention

    func testOversizedEntryIsNotRetained() {
        // Minimum possible cost is 256 (overhead alone); a limit of 100 rejects everything.
        let cache = Cache(maxEntryCount: 100, maxCostBytes: 100)
        cache.set(payload("x"), for: key(1))
        XCTAssertEqual(cache.entryCountForTesting, 0)
        XCTAssertNil(cache.get(key(1)))
    }

    func testOversizedEntryDoesNotEvictExistingEntries() {
        let small = payload("ok")
        let smallCost = Cache.estimateCostForTesting(small)
        // maxCostBytes fits `small` once but not the oversized `big`.
        let big = payload(String(repeating: "x", count: 400))  // cost = 256 + 800 = 1056
        let cache = Cache(maxEntryCount: 100, maxCostBytes: smallCost * 2)

        cache.set(small, for: key(1))
        XCTAssertEqual(cache.entryCountForTesting, 1)

        cache.set(big, for: key(2))  // big.cost > maxCostBytes → not retained, no eviction
        XCTAssertEqual(cache.entryCountForTesting, 1)
        XCTAssertTrue(cache.containsForTesting(key(1)),
            "Existing entries must not be evicted by an oversized insert")
        XCTAssertFalse(cache.containsForTesting(key(2)))
    }

    func testOversizedReplacementPreservesExistingEntry() {
        let small = payload("ok")
        let smallCost = Cache.estimateCostForTesting(small)
        let cache = Cache(maxEntryCount: 100, maxCostBytes: smallCost)
        let existingKey = key(1)

        cache.set(small, for: existingKey)
        cache.set(payload(String(repeating: "x", count: 400)), for: existingKey)

        XCTAssertEqual(cache.get(existingKey)?.attributedString.string, "ok")
        XCTAssertEqual(cache.entryCountForTesting, 1)
        XCTAssertEqual(cache.totalRetainedCostForTesting, smallCost)
    }

    // MARK: - Replacement accounting and promotion

    func testReplacementUpdatesAccountingExactly() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let k = key(1)
        let p1 = payload("hi")
        let p2 = payload("hello, world!")

        cache.set(p1, for: k)
        let costAfterFirst = cache.totalRetainedCostForTesting

        cache.set(p2, for: k)  // replace

        let delta = Cache.estimateCostForTesting(p2) - Cache.estimateCostForTesting(p1)
        XCTAssertEqual(cache.totalRetainedCostForTesting, costAfterFirst + delta,
            "Replacement must update totalCost by the difference of old and new entry costs")
        XCTAssertEqual(cache.entryCountForTesting, 1, "Replacement must not change entry count")
    }

    func testReplacementPromotesToMRU() {
        let cache = Cache(maxEntryCount: 3, maxCostBytes: Int.max)
        let k1 = key(1), k2 = key(2), k3 = key(3), k4 = key(4)

        cache.set(payload("a"),   for: k1)  // LRU after k2, k3
        cache.set(payload("bb"),  for: k2)
        cache.set(payload("ccc"), for: k3)  // MRU; order: k3 → k2 → k1(LRU)

        cache.set(payload("replaced"), for: k1)  // replacement promotes k1 to MRU
        // New list order: k1(MRU) → k3 → k2(LRU)

        cache.set(payload("d"), for: k4)  // count 4 > 3 → evict k2
        XCTAssertTrue(cache.containsForTesting(k1),
            "Replaced entry was promoted to MRU; must not be evicted")
        XCTAssertFalse(cache.containsForTesting(k2),
            "k2 became LRU after replacement promotion; must be evicted")
        XCTAssertTrue(cache.containsForTesting(k3))
        XCTAssertTrue(cache.containsForTesting(k4))
    }

    func testReplacedPayloadIsVisible() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        let k = key(1)
        cache.set(payload("v1"), for: k)
        cache.set(payload("v2"), for: k)
        XCTAssertEqual(cache.get(k)?.attributedString.string, "v2")
    }

    // MARK: - Zero / negative limits

    func testZeroEntryLimitStoresNothing() {
        let cache = Cache(maxEntryCount: 0, maxCostBytes: Int.max)
        cache.set(payload("x"), for: key(1))
        XCTAssertEqual(cache.entryCountForTesting, 0)
        XCTAssertNil(cache.get(key(1)))
    }

    func testZeroCostLimitStoresNothing() {
        let cache = Cache(maxEntryCount: 100, maxCostBytes: 0)
        cache.set(payload("x"), for: key(1))
        XCTAssertEqual(cache.entryCountForTesting, 0)
        XCTAssertNil(cache.get(key(1)))
    }

    func testNegativeEntryLimitSanitizedToZero() {
        let cache = Cache(maxEntryCount: -5, maxCostBytes: Int.max)
        XCTAssertEqual(cache.maxEntryCount, 0)
        cache.set(payload("x"), for: key(1))
        XCTAssertEqual(cache.entryCountForTesting, 0)
    }

    func testNegativeCostLimitSanitizedToZero() {
        let cache = Cache(maxEntryCount: 100, maxCostBytes: -1)
        XCTAssertEqual(cache.maxCostBytes, 0)
        cache.set(payload("x"), for: key(1))
        XCTAssertEqual(cache.entryCountForTesting, 0)
    }

    // MARK: - Arithmetic cost inclusion

    func testArithmeticPlanCostIsPositiveForNonemptyString() {
        let cost = Cache.estimateCostForTesting(
            Payload(attributedString: NSAttributedString(string: "abc"),
                    measurementPlan: .arithmetic(preparedText(segments: 5)))
        )
        XCTAssertGreaterThan(cost, 0)
    }

    func testArithmeticPlanCostsMoreThanTextKitForSameString() {
        let str = NSAttributedString(string: "hello world")
        let textKitCost = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .textKit)
        )
        let arithmeticCost = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .arithmetic(preparedText(segments: 10)))
        )
        XCTAssertGreaterThan(arithmeticCost, textKitCost,
            "Arithmetic plan with segments must cost more than textKit for the same string")
    }

    func testArithmeticCostScalesWithSegmentCount() {
        let str = NSAttributedString(string: "t")
        let cost5 = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .arithmetic(preparedText(segments: 5)))
        )
        let cost20 = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .arithmetic(preparedText(segments: 20)))
        )
        XCTAssertGreaterThan(cost20, cost5)
    }

    func testArithmeticCostIncludesParagraphStorage() {
        let str = NSAttributedString(string: "t")
        let withoutParagraphs = preparedText(segments: 1)
        var withParagraphs = withoutParagraphs
        withParagraphs.paragraphs = [
            ArithmeticTextCalculator.Paragraph(
                chunkRange: 0..<1,
                firstLineHeadIndent: 0,
                headIndent: 0,
                paragraphSpacingBefore: 0,
                paragraphSpacingAfter: 0,
                emptyLineHeight: 14
            ),
            ArithmeticTextCalculator.Paragraph(
                chunkRange: 1..<1,
                firstLineHeadIndent: 0,
                headIndent: 0,
                paragraphSpacingBefore: 0,
                paragraphSpacingAfter: 0,
                emptyLineHeight: 14
            )
        ]

        let withoutParagraphCost = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .arithmetic(withoutParagraphs))
        )
        let withParagraphCost = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .arithmetic(withParagraphs))
        )

        XCTAssertEqual(
            withParagraphCost - withoutParagraphCost,
            2 * MemoryLayout<ArithmeticTextCalculator.Paragraph>.stride
        )
    }

    func testCodeBlockInsetAndTextKitHaveEqualCostForSameString() {
        let str = NSAttributedString(string: "var x = 1")
        let textKitCost = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .textKit)
        )
        let insetCost = Cache.estimateCostForTesting(
            Payload(attributedString: str, measurementPlan: .codeBlockInset)
        )
        XCTAssertEqual(insetCost, textKitCost,
            "codeBlockInset adds no segment storage; cost must equal textKit for the same string")
    }

    // MARK: - Clear

    func testClearRemovesAllEntriesAndResetsAccounting() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        cache.set(payload("a"), for: key(1))
        cache.set(payload("b"), for: key(2))
        XCTAssertGreaterThan(cache.entryCountForTesting, 0)
        XCTAssertGreaterThan(cache.totalRetainedCostForTesting, 0)

        cache.clear()

        XCTAssertEqual(cache.entryCountForTesting, 0)
        XCTAssertEqual(cache.totalRetainedCostForTesting, 0)
        XCTAssertNil(cache.get(key(1)))
        XCTAssertNil(cache.get(key(2)))
    }

    func testClearPreservesDiagnosticCounters() {
        let cache = Cache(maxEntryCount: 10, maxCostBytes: Int.max)
        cache.set(payload("a"), for: key(1))
        _ = cache.get(key(1))    // 1 hit
        _ = cache.get(key(99))   // 1 miss
        cache.clear()
        XCTAssertEqual(cache.hitCountForTesting, 1,  "clear() must not reset hit counter")
        XCTAssertEqual(cache.missCountForTesting, 1, "clear() must not reset miss counter")
    }

    func testConcurrentAccessPreservesStrictBounds() {
        let cache = Cache(maxEntryCount: 32, maxCostBytes: 64 * 1_024)

        DispatchQueue.concurrentPerform(iterations: 1_000) { index in
            let entryKey = Key(
                contentHash: index % 64,
                interactionHash: nil,
                variantHash: index % 3
            )
            let entryPayload = Payload(
                attributedString: NSAttributedString(string: "entry \(index)"),
                measurementPlan: .textKit
            )
            cache.set(entryPayload, for: entryKey)
            _ = cache.get(entryKey)
        }

        XCTAssertLessThanOrEqual(cache.entryCountForTesting, 32)
        XCTAssertLessThanOrEqual(cache.totalRetainedCostForTesting, 64 * 1_024)
    }
}
