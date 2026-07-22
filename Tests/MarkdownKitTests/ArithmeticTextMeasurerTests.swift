import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Covers `ArithmeticTextMeasurer.WidthCache`: the structured, lock-owned width
/// cache that replaced the interpolated-`NSString`/`NSNumber`-boxed `NSCache`.
final class ArithmeticTextMeasurerTests: XCTestCase {

    private typealias Key = ArithmeticTextMeasurer.WidthCache.Key

    /// Mirrors the production rounding formula (`Int((pointSize * 1000).rounded())`)
    /// used by `ArithmeticTextMeasurer`'s private `FontCacheKey` so boundary tests
    /// exercise the same 1/1000-point resolution.
    private func milli(_ pointSize: CGFloat) -> Int {
        Int((pointSize * 1000).rounded())
    }

    // MARK: - Key identity contracts

    func testDelimiterCollisionKeysRemainDistinct() {
        // Under the old "\(fontName)|\(milli)|\(text)" interpolation these two
        // logically different identities produced an identical cache key string.
        // The structured, typed key must keep them distinct.
        let keyA = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "|13000|x")
        let keyB = Key(fontName: "Helvetica|13000|x", pointSizeMilli: 12_000, text: "")
        XCTAssertNotEqual(keyA, keyB)

        let keyC = Key(fontName: "A", pointSizeMilli: 1, text: "|1|text")
        let keyD = Key(fontName: "A|1", pointSizeMilli: 1, text: "text")
        XCTAssertNotEqual(keyC, keyD)

        let keyE = Key(fontName: "A|1|text", pointSizeMilli: 1, text: "")
        XCTAssertNotEqual(keyC, keyE)
        XCTAssertNotEqual(keyD, keyE)
    }

    func testFontNameSeparation() {
        let keyA = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "abc")
        let keyB = Key(fontName: "Courier", pointSizeMilli: 12_000, text: "abc")
        XCTAssertNotEqual(keyA, keyB)
        XCTAssertEqual(keyA, Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "abc"))
    }

    func testRoundedPointSizeBoundarySeparationAndEquality() {
        // 12.0004 -> 12000.4 -> rounds to 12000; 12.0006 -> 12000.6 -> rounds to 12001.
        let milliBelow = milli(12.0004)
        let milliAbove = milli(12.0006)
        XCTAssertEqual(milliBelow, 12_000)
        XCTAssertEqual(milliAbove, 12_001)
        XCTAssertNotEqual(
            Key(fontName: "Helvetica", pointSizeMilli: milliBelow, text: "x"),
            Key(fontName: "Helvetica", pointSizeMilli: milliAbove, text: "x")
        )

        // Two distinct point sizes that round to the same milli value collapse to
        // an equal key, matching the prior identity semantics exactly.
        let milliA = milli(12.00001)
        let milliB = milli(12.00002)
        XCTAssertEqual(milliA, milliB)
        XCTAssertEqual(
            Key(fontName: "Helvetica", pointSizeMilli: milliA, text: "x"),
            Key(fontName: "Helvetica", pointSizeMilli: milliB, text: "x")
        )
    }

    func testExactUnicodeTextSeparation() {
        // Distinct emoji ZWJ/skin-tone-modifier sequences: not canonically
        // equivalent, so they must key separately.
        let thumbsUp = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "👍")
        let thumbsUpToned = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "👍🏽")
        XCTAssertNotEqual(thumbsUp, thumbsUpToned)

        // An astral (surrogate-pair) scalar is distinct from unrelated BMP text of
        // the same UTF-16 length.
        let astral = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "𝄞")
        let bmp = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "ab")
        XCTAssertNotEqual(astral, bmp)

        // Same exact scalar sequence keys identically (segment-text identity is
        // preserved verbatim, not weakened by folding or hashing).
        XCTAssertEqual(
            Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "café"),
            Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "café")
        )
        XCTAssertNotEqual(
            Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "café"),
            Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "cafe")
        )
    }

    func testPrecomposedAndDecomposedUnicodeRemainDistinctByExactUTF8Encoding() {
        let precomposed = "café"
        let decomposed = "cafe\u{0301}" // "e" + combining acute accent (U+0301)

        // Sanity check: Swift's `String` equality is canonical-equivalence based,
        // so these two distinctly-encoded scalar sequences compare equal at the
        // `String` level — this is exactly the weakening the `Key` type must not
        // inherit.
        XCTAssertEqual(precomposed, decomposed)
        XCTAssertNotEqual(Array(precomposed.utf8), Array(decomposed.utf8))

        let keyPrecomposed = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: precomposed)
        let keyDecomposed = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: decomposed)
        XCTAssertNotEqual(keyPrecomposed, keyDecomposed)

        // The same distinction must hold for the font-name component, not just text.
        let keyFontPrecomposed = Key(fontName: precomposed, pointSizeMilli: 12_000, text: "x")
        let keyFontDecomposed = Key(fontName: decomposed, pointSizeMilli: 12_000, text: "x")
        XCTAssertNotEqual(keyFontPrecomposed, keyFontDecomposed)

        // The distinction is observable end-to-end through the cache: both keys
        // must be stored and retrieved independently rather than colliding.
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 4)
        cache.insert(1.0, for: keyPrecomposed)
        cache.insert(2.0, for: keyDecomposed)
        XCTAssertEqual(cache.value(for: keyPrecomposed), 1.0)
        XCTAssertEqual(cache.value(for: keyDecomposed), 2.0)
        XCTAssertEqual(cache.countForTesting, 2)
    }

    // MARK: - Direct CGFloat value contract

    func testDirectCGFloatRoundTrip() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 4)
        let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "abc")
        let width: CGFloat = 123.456

        cache.insert(width, for: key)

        XCTAssertEqual(cache.value(for: key), width)
    }

    func testMissReturnsNil() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 4)
        let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "abc")

        XCTAssertNil(cache.value(for: key))
    }

    // MARK: - Capacity and strict FIFO eviction contracts

    func testZeroCapacityRetainsNothing() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 0)
        let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "abc")

        cache.insert(1.0, for: key)

        XCTAssertNil(cache.value(for: key))
        XCTAssertEqual(cache.countForTesting, 0)
    }

    func testNegativeCapacityRetainsNothing() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: -5)
        let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "abc")

        cache.insert(1.0, for: key)

        XCTAssertNil(cache.value(for: key))
        XCTAssertEqual(cache.countForTesting, 0)
    }

    func testStrictFIFOReplacement() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 3)
        let keys = (0..<3).map { Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "k\($0)") }
        for (index, key) in keys.enumerated() {
            cache.insert(CGFloat(index), for: key)
        }
        XCTAssertEqual(cache.countForTesting, 3)

        // A 4th distinct key evicts the oldest surviving key (k0) in strict
        // insertion order.
        let key3 = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "k3")
        cache.insert(3.0, for: key3)

        XCTAssertEqual(cache.countForTesting, 3)
        XCTAssertNil(cache.value(for: keys[0]))
        XCTAssertEqual(cache.value(for: keys[1]), 1.0)
        XCTAssertEqual(cache.value(for: keys[2]), 2.0)
        XCTAssertEqual(cache.value(for: key3), 3.0)

        // The next insertion evicts k1, the next-oldest surviving key.
        let key4 = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "k4")
        cache.insert(4.0, for: key4)

        XCTAssertNil(cache.value(for: keys[1]))
        XCTAssertEqual(cache.value(for: keys[2]), 2.0)
        XCTAssertEqual(cache.value(for: key3), 3.0)
        XCTAssertEqual(cache.value(for: key4), 4.0)
    }

    func testRepeatedInsertOfExistingKeyDoesNotGrowCountOrCorruptEvictionOrder() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 2)
        let keyA = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "a")
        let keyB = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "b")

        cache.insert(1.0, for: keyA)
        cache.insert(2.0, for: keyB)
        XCTAssertEqual(cache.countForTesting, 2)

        // Re-inserting keyA with a new value must not grow the count and must not
        // move its slot in the FIFO ring.
        cache.insert(10.0, for: keyA)
        XCTAssertEqual(cache.countForTesting, 2)
        XCTAssertEqual(cache.value(for: keyA), 10.0)

        // The next new key must still evict keyA (the oldest by insertion order),
        // proving the repeated update did not refresh its FIFO position.
        let keyC = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "c")
        cache.insert(3.0, for: keyC)

        XCTAssertNil(cache.value(for: keyA))
        XCTAssertEqual(cache.value(for: keyB), 2.0)
        XCTAssertEqual(cache.value(for: keyC), 3.0)
    }

    // MARK: - `removeAll()` (memory-pressure purge contract)

    func testRemoveAllClearsCountAndValuesAndResetsFIFOAfterRefill() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 2)
        let keyA = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "a")
        let keyB = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "b")
        let keyC = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "c")

        // Fill and wrap the ring at least once before purging, so the reset must
        // clear a non-trivial `writeIndex`, not just an empty/just-filled cache.
        cache.insert(1.0, for: keyA)
        cache.insert(2.0, for: keyB)
        cache.insert(3.0, for: keyC) // evicts keyA
        XCTAssertEqual(cache.countForTesting, 2)

        cache.removeAll()

        XCTAssertEqual(cache.countForTesting, 0)
        XCTAssertNil(cache.value(for: keyA))
        XCTAssertNil(cache.value(for: keyB))
        XCTAssertNil(cache.value(for: keyC))

        // Refilling after the purge must behave exactly like a freshly created
        // cache: the first `capacity` distinct keys are retained without
        // eviction, and only the next new key evicts the oldest of *this*
        // generation (keyA), not a stale ring position left over from before
        // the purge.
        cache.insert(10.0, for: keyA)
        cache.insert(20.0, for: keyB)
        XCTAssertEqual(cache.countForTesting, 2)
        XCTAssertEqual(cache.value(for: keyA), 10.0)
        XCTAssertEqual(cache.value(for: keyB), 20.0)

        let keyD = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "d")
        cache.insert(4.0, for: keyD)

        XCTAssertEqual(cache.countForTesting, 2)
        XCTAssertNil(cache.value(for: keyA))
        XCTAssertEqual(cache.value(for: keyB), 20.0)
        XCTAssertEqual(cache.value(for: keyD), 4.0)
    }

    func testRemoveAllOnEmptyCacheIsANoOp() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 4)

        cache.removeAll()

        XCTAssertEqual(cache.countForTesting, 0)
    }

    // MARK: - UIKit memory-pressure wiring

#if canImport(UIKit) && !os(watchOS)
    /// The production `cachedWidths` singleton opts into `observesMemoryPressure`
    /// so the OS can purge it under memory pressure. This exercises that same
    /// UIKit notification wiring end-to-end on a locally owned cache instance
    /// (never the shared singleton), confirming the observer synchronously
    /// clears the cache and is torn down by normal `deinit` — no production
    /// hooks are added to make this observable.
    func testMemoryWarningNotificationClearsCacheWhenObservingMemoryPressure() {
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: 2, observesMemoryPressure: true)
        let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "memory-warning")
        cache.insert(1.0, for: key)
        XCTAssertEqual(cache.countForTesting, 1)

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        XCTAssertEqual(
            cache.countForTesting, 0,
            "UIKit memory-warning notification must synchronously clear a cache that opted into observesMemoryPressure"
        )
        XCTAssertNil(cache.value(for: key))
    }
#endif

    func testConcurrentReadsAndWritesCompleteCorrectlyWithoutExpectedEviction() {
        let iterations = 1_000
        let cache = ArithmeticTextMeasurer.WidthCache(capacity: iterations * 2)

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "k\(index)")
            cache.insert(CGFloat(index), for: key)
            _ = cache.value(for: key)
        }

        for index in 0..<iterations {
            let key = Key(fontName: "Helvetica", pointSizeMilli: 12_000, text: "k\(index)")
            XCTAssertEqual(cache.value(for: key), CGFloat(index))
        }
        XCTAssertEqual(cache.countForTesting, iterations)
    }

    // MARK: - `prepare(attributedString:)` call contract

    func testPrepareProducesStableWidthsAcrossRepeatedCalls() {
        let font = Font.systemFont(ofSize: 16)
        let attributedString = NSAttributedString(string: "Hello, world!", attributes: [.font: font])

        let first = ArithmeticTextMeasurer.prepare(attributedString: attributedString)
        let second = ArithmeticTextMeasurer.prepare(attributedString: attributedString)

        XCTAssertFalse(first.widths.isEmpty)
        XCTAssertEqual(first.widths, second.widths)
        XCTAssertEqual(first.segmentTexts, second.segmentTexts)
    }

    func testPrepareDistinguishesDifferentTextAtSameFont() {
        let font = Font.systemFont(ofSize: 16)
        let short = NSAttributedString(string: "I", attributes: [.font: font])
        let long = NSAttributedString(string: "WWWWWWWWWW", attributes: [.font: font])

        let shortPrepared = ArithmeticTextMeasurer.prepare(attributedString: short)
        let longPrepared = ArithmeticTextMeasurer.prepare(attributedString: long)

        XCTAssertLessThan(shortPrepared.widths.reduce(0, +), longPrepared.widths.reduce(0, +))
    }
}
