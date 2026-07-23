import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
private final class ReentrantTextAttachmentCell: NSTextAttachmentCell {
    nonisolated(unsafe) private(set) var nestedSize: CGSize = .zero

    override func cellSize() -> NSSize {
        if nestedSize == .zero {
            nestedSize = TextKitCalculator().calculateSize(
                for: NSAttributedString(
                    string: "Nested attachment callback layout",
                    attributes: [.font: NSFont.systemFont(ofSize: 13)]
                ),
                constrainedToWidth: 160
            )
        }
        return NSSize(width: 8, height: 8)
    }
}
#endif

private final class OversizedSliceBarrier: @unchecked Sendable {
    struct Snapshot {
        let sliceCount: Int
        let arithmeticWasCancelled: Bool?
        let waiterProducedGeometry: Bool
    }

    let firstSliceReached: XCTestExpectation
    let arithmeticFinished: XCTestExpectation
    let waiterFinished: XCTestExpectation

    private let lock = NSLock()
    private let releaseFirstSlice = DispatchSemaphore(value: 0)
    private var didPauseFirstSlice = false
    private var sliceCount = 0
    private var arithmeticWasCancelled: Bool?
    private var waiterProducedGeometry = false

    init(
        firstSliceReached: XCTestExpectation,
        arithmeticFinished: XCTestExpectation,
        waiterFinished: XCTestExpectation
    ) {
        self.firstSliceReached = firstSliceReached
        self.arithmeticFinished = arithmeticFinished
        self.waiterFinished = waiterFinished
    }

    func oversizedSliceCompleted() {
        lock.lock()
        sliceCount += 1
        let shouldPause = !didPauseFirstSlice
        didPauseFirstSlice = true
        lock.unlock()

        if shouldPause {
            firstSliceReached.fulfill()
            releaseFirstSlice.wait()
        }
    }

    func releaseArithmetic() {
        releaseFirstSlice.signal()
    }

    func recordArithmeticFinished(wasCancelled: Bool) {
        lock.lock()
        arithmeticWasCancelled = wasCancelled
        lock.unlock()
        arithmeticFinished.fulfill()
    }

    func recordWaiterFinished(size: CGSize) {
        lock.lock()
        waiterProducedGeometry = size.width > 0 && size.height > 0
        lock.unlock()
        waiterFinished.fulfill()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            sliceCount: sliceCount,
            arithmeticWasCancelled: arithmeticWasCancelled,
            waiterProducedGeometry: waiterProducedGeometry
        )
    }
}

/// Multi-actor stress tests that exercise LayoutSolver concurrency boundaries.
/// Validates the @unchecked Sendable contract documented in ConcurrencyContract.md.
final class ConcurrencyStressTests: XCTestCase {

    private struct LayoutMetrics: Sendable {
        let height: CGFloat
        let childCount: Int
    }

    /// Exercise LayoutSolver from multiple concurrent tasks to detect data races.
    /// Each task creates its own parse → solve pipeline to comply with strict concurrency.
    func testConcurrentLayoutSolverAccess() async throws {
        let markdown = "Hello **world**"

        let results = await withTaskGroup(of: LayoutMetrics.self, returning: [LayoutMetrics].self) { group in
            for width in stride(from: 200.0, through: 800.0, by: 100.0) {
                group.addTask {
                    let doc = MarkdownParser().parse(markdown)
                    let solver = LayoutSolver()
                    let result = await solver.solve(node: doc, constrainedToWidth: CGFloat(width))
                    // Check children (paragraph layouts) rather than document-level size
                    let firstChildHeight = result.children.first?.size.height ?? 0
                    return LayoutMetrics(height: firstChildHeight, childCount: result.children.count)
                }
            }

            var collected: [LayoutMetrics] = []
            for await metric in group {
                collected.append(metric)
            }
            return collected
        }

        XCTAssertEqual(results.count, 7)
        for metric in results {
            XCTAssertGreaterThan(metric.childCount, 0, "Document should have child layouts")
            XCTAssertGreaterThan(metric.height, 0, "Child layout should have non-zero height")
        }
    }

    /// Cold fallback shaping and TextKit layout share one process-wide safety
    /// gate so CoreText cannot mutate its fallback-font dictionaries from two
    /// independent layout paths at once. The gate must also permit synchronous
    /// same-thread reentry from a host-provided attachment cell.
    func testConcurrentColdFallbackShapingAndTextKitLayoutRemainStable() async {
        let firstSliceReached = expectation(description: "first oversized slice reached")
        let arithmeticFinished = expectation(description: "oversized arithmetic finished")
        let waiterFinished = expectation(description: "TextKit waiter finished")
        let barrier = OversizedSliceBarrier(
            firstSliceReached: firstSliceReached,
            arithmeticFinished: arithmeticFinished,
            waiterFinished: waiterFinished
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let font = Font.systemFont(ofSize: 16)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let attributedString = NSAttributedString(
                string: String(repeating: "W", count: 2_048),
                attributes: [.font: font, .paragraphStyle: style]
            )
            let calculator = ArithmeticTextCalculator()
            let prepared = calculator.prepare(attributedString: attributedString)
            let outcome = calculator.layoutOutcome(
                prepared: prepared,
                constrainedToWidth: 4,
                onOversizedLine: barrier.oversizedSliceCompleted
            )
            barrier.recordArithmeticFinished(wasCancelled: outcome.wasCancelled)
        }

        await fulfillment(of: [firstSliceReached], timeout: 2)
        XCTAssertNil(
            barrier.snapshot().arithmeticWasCancelled,
            "The arithmetic worker must still be paused between slices"
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let size = TextKitCalculator().calculateSize(
                for: NSAttributedString(
                    string: "Independent TextKit waiter",
                    attributes: [.font: Font.systemFont(ofSize: 13)]
                ),
                constrainedToWidth: 180
            )
            barrier.recordWaiterFinished(size: size)
        }

        await fulfillment(of: [waiterFinished], timeout: 2)
        XCTAssertNil(
            barrier.snapshot().arithmeticWasCancelled,
            "TextKit must acquire the gate while arithmetic is paused outside it"
        )
        barrier.releaseArithmetic()
        await fulfillment(of: [arithmeticFinished], timeout: 5)

        let barrierSnapshot = barrier.snapshot()
        XCTAssertGreaterThan(barrierSnapshot.sliceCount, 1)
        XCTAssertEqual(barrierSnapshot.arithmeticWasCancelled, false)
        XCTAssertTrue(barrierSnapshot.waiterProducedGeometry)

        #if canImport(AppKit)
        await MainActor.run {
            let cell = ReentrantTextAttachmentCell()
            let attachment = NSTextAttachment()
            attachment.attachmentCell = cell
            let outerAttributedString = NSMutableAttributedString(string: "Before ")
            outerAttributedString.append(NSAttributedString(attachment: attachment))
            outerAttributedString.append(NSAttributedString(string: " after"))

            let outerSize = TextKitCalculator().calculateSize(
                for: outerAttributedString,
                constrainedToWidth: 200
            )
            XCTAssertGreaterThan(outerSize.width, 0)
            XCTAssertGreaterThan(outerSize.height, 0)
            XCTAssertGreaterThan(cell.nestedSize.width, 0)
            XCTAssertGreaterThan(cell.nestedSize.height, 0)
        }
        #endif

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for index in 0..<48 {
                group.addTask {
                    let font = Font.systemFont(ofSize: 12 + CGFloat(index) * 0.01)
                    let style = NSMutableParagraphStyle()
                    style.lineBreakMode = .byWordWrapping
                    style.lineHeightMultiple = 1.2
                    let attributedString = NSAttributedString(
                        string: "☐ Task \(index) and ▌ quote fallback shaping",
                        attributes: [.font: font, .paragraphStyle: style]
                    )
                    let size: CGSize
                    if index.isMultiple(of: 2) {
                        size = ArithmeticTextCalculator().calculateSize(
                            for: attributedString,
                            constrainedToWidth: 140
                        )
                    } else {
                        size = TextKitCalculator().calculateSize(
                            for: attributedString,
                            constrainedToWidth: 140
                        )
                    }
                    return size.width.isFinite && size.height.isFinite
                        && size.width > 0 && size.height > 0
                }
            }

            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, 48)
        XCTAssertTrue(results.allSatisfy { $0 })
    }

    /// Exercise concurrent solve at varying widths with cache reuse.
    func testConcurrentSolveAtVaryingWidths() async throws {
        let markdown = "Hello **world**"

        let results = await withTaskGroup(of: LayoutMetrics.self, returning: [LayoutMetrics].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let doc = MarkdownParser().parse(markdown)
                    let solver = LayoutSolver()
                    _ = await solver.solve(node: doc, constrainedToWidth: 400)
                    let result = await solver.solve(
                        node: doc,
                        constrainedToWidth: CGFloat.random(in: 200...800)
                    )
                    let firstChildHeight = result.children.first?.size.height ?? 0
                    return LayoutMetrics(height: firstChildHeight, childCount: result.children.count)
                }
            }

            var collected: [LayoutMetrics] = []
            for await metric in group {
                collected.append(metric)
            }
            return collected
        }

        XCTAssertEqual(results.count, 10)
        for metric in results {
            XCTAssertGreaterThan(metric.height, 0, "Child layout should have non-zero height")
            XCTAssertGreaterThan(metric.childCount, 0, "Document should have child layouts")
        }
    }

    /// Constructs each parser (and its plugin-free pipeline) inside its own task with a
    /// distinct per-instance `ResourceLimits`, proving limits are task-confined and do not
    /// leak across concurrent parses. `MarkdownParser` is intentionally **not** `Sendable`
    /// (its `plugins` array may hold non-`Sendable` host types), so each task below
    /// constructs and uses its own parser value entirely locally — no configured parser or
    /// plugin instance is shared or copied across tasks.
    func testConcurrentPerInstanceResourceLimitsDoNotLeak() async throws {
        struct OutcomeSummary: Sendable, Equatable {
            let configuredMaxBytes: Int
            let isRejected: Bool
        }

        // Half the tasks use a tiny byte ceiling (so a fixed oversized payload is rejected),
        // the other half use a generous ceiling (so the same payload is accepted). If limits
        // leaked between task-confined parser instances, some outcomes would flip.
        let payload = String(repeating: "a", count: 500)

        let results = await withTaskGroup(of: OutcomeSummary.self, returning: [OutcomeSummary].self) { group in
            for index in 0..<20 {
                group.addTask {
                    let useTinyLimit = index % 2 == 0
                    let maxBytes = useTinyLimit ? 10 : 1_048_576
                    let limits = MarkdownParser.ResourceLimits(maximumInputBytes: maxBytes)
                    let parser = MarkdownParser(plugins: [], limits: limits)
                    let outcome = parser.parseOutcome(payload)
                    return OutcomeSummary(configuredMaxBytes: maxBytes, isRejected: outcome.isRejected)
                }
            }

            var collected: [OutcomeSummary] = []
            for await summary in group {
                collected.append(summary)
            }
            return collected
        }

        XCTAssertEqual(results.count, 20)
        for summary in results {
            if summary.configuredMaxBytes == 10 {
                XCTAssertTrue(summary.isRejected, "Tiny-limit parser should reject the oversized payload")
            } else {
                XCTAssertFalse(summary.isRejected, "Generous-limit parser should accept the same payload")
            }
        }
    }

    /// Exercise concurrent parse + solve on the same markdown at the same width.
    /// All results should have identical dimensions (deterministic output).
    func testConcurrentSolveProducesDeterministicResults() async throws {
        let markdown = "Hello **world**"

        let results = await withTaskGroup(of: LayoutMetrics.self, returning: [LayoutMetrics].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let doc = MarkdownParser().parse(markdown)
                    let solver = LayoutSolver()
                    let result = await solver.solve(node: doc, constrainedToWidth: 400)
                    let firstChildHeight = result.children.first?.size.height ?? 0
                    return LayoutMetrics(height: firstChildHeight, childCount: result.children.count)
                }
            }

            var collected: [LayoutMetrics] = []
            for await metric in group {
                collected.append(metric)
            }
            return collected
        }

        XCTAssertEqual(results.count, 10)
        let heights = Set(results.map { Int($0.height.rounded()) })
        XCTAssertEqual(heights.count, 1,
            "Concurrent solvers should produce deterministic heights")
    }
}
