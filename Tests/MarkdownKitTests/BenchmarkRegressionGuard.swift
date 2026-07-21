import Foundation
import XCTest

/// Regression guardrails for benchmark tests.
///
/// Baseline source: `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json`, the
/// single machine-readable baseline shared with `scripts/render_benchmark_baseline.py`
/// (which renders it into `docs/BENCHMARK_BASELINE.md`). Absolute timing values
/// and policies are decoded through `BenchmarkBaselineLoader`; same-process
/// relational workloads keep only their exact key contracts here.
enum BenchmarkRegressionGuard {

    static let preparedContentRelayoutBudgetRatio = 0.60

    static let preparedContentRelayoutExpectedKeys: Set<String> = [
        "solve(cold-first)(large)",
        "solve(width-sweep)(large)",
        "solve(rebuild-sweep)(large)"
    ]

    // MARK: - Focused entry points

    /// Canonical guard for `testPhase1_Parse`. Checks every `parse(*)` key in `core.parse`.
    static func assertCoreParse(
        parseResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let baseline = BenchmarkBaselineLoader.load(file: file, line: line) else { return }
        assertGroup(
            parseResults,
            group: .coreParse,
            baseline: baseline,
            isGuardedFamily: { $0.label == "parse" },
            file: file,
            line: line
        )
    }

    /// Canonical guard for `testPhase2_Layout`. Checks every `solve(*)` key in `core.layout`.
    static func assertCoreLayout(
        layoutResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let baseline = BenchmarkBaselineLoader.load(file: file, line: line) else { return }
        assertGroup(
            layoutResults,
            group: .coreLayout,
            baseline: baseline,
            isGuardedFamily: { $0.label == "solve" },
            file: file,
            line: line
        )
    }

    /// Canonical guard for `testCacheHitMissRates`. Checks `core.cache` keys and
    /// asserts warm-cache dominates cold.
    static func assertCoreCache(
        cacheResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let baseline = BenchmarkBaselineLoader.load(file: file, line: line) else { return }
        assertGroup(
            cacheResults,
            group: .coreCache,
            baseline: baseline,
            isGuardedFamily: { $0.label.hasPrefix("solve(") },
            file: file,
            line: line
        )
        assertWarmCacheImproves(cacheResults, file: file, line: line)
    }

    /// Canonical guard for `testConcurrentSolveStress`. Checks `deep.concurrency` keys
    /// and asserts concurrent solve is not slower than sequential.
    static func assertDeepConcurrency(
        concurrencyResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let baseline = BenchmarkBaselineLoader.load(file: file, line: line) else { return }
        assertGroup(
            concurrencyResults,
            group: .deepConcurrency,
            baseline: baseline,
            isGuardedFamily: { _ in true },
            file: file,
            line: line
        )
        assertConcurrencyIsNotSlower(concurrencyResults, file: file, line: line)
    }

    /// Canonical guard for `testRapidUpdateLatestSettledLatency`. Checks the
    /// `coordinator.streaming` key `latest-settled(large-3-updates)`.
    static func assertCoordinatorStreaming(
        streamingResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let baseline = BenchmarkBaselineLoader.load(file: file, line: line) else { return }
        assertGroup(
            streamingResults,
            group: .coordinatorStreaming,
            baseline: baseline,
            isGuardedFamily: { $0.label == "latest-settled" },
            file: file,
            line: line
        )
    }

    static func assertPreparedContentRelayout(
        results: [BenchmarkResult],
        widthCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard widthCount > 1 else {
            XCTFail(
                "Prepared-content relayout guard requires widthCount > 1; got \(widthCount).",
                file: file,
                line: line
            )
            return
        }

        var measuredByKey: [String: BenchmarkResult] = [:]
        for result in results {
            let resultKey = key(for: result)
            if measuredByKey.updateValue(result, forKey: resultKey) != nil {
                XCTFail(
                    "Prepared-content relayout produced duplicate result key \(resultKey).",
                    file: file,
                    line: line
                )
                return
            }
        }
        let measuredKeys = Set(measuredByKey.keys)
        guard measuredKeys == preparedContentRelayoutExpectedKeys else {
            XCTFail(
                """
                Prepared-content relayout workload keys mismatch: expected \
                \(preparedContentRelayoutExpectedKeys.sorted()), got \(measuredKeys.sorted()).
                """,
                file: file,
                line: line
            )
            return
        }

        guard let baseline = BenchmarkBaselineLoader.load(file: file, line: line) else { return }

        let cold = measuredByKey["solve(cold-first)(large)"]!
        let widthSweep = measuredByKey["solve(width-sweep)(large)"]!
        let rebuildSweep = measuredByKey["solve(rebuild-sweep)(large)"]!

        // Cold p95 is retained as five-process stage evidence. Persistent timing
        // policy remains average-baseline guards plus this same-process relation.
        for (keyName, result) in [
            ("solve(cold-first)(large)", cold),
            ("solve(width-sweep)(large)", widthSweep),
            ("solve(rebuild-sweep)(large)", rebuildSweep)
        ] {
            assertHarnessMatches(result, key: keyName, baseline: baseline, file: file, line: line)
        }

        guard let avgBudget = preparedContentRelayoutBudget(rebuildMetric: rebuildSweep.avg, widthCount: widthCount),
              let p95Budget = preparedContentRelayoutBudget(rebuildMetric: rebuildSweep.p95, widthCount: widthCount) else {
            XCTFail(
                "Prepared-content relayout guard could not derive a rebuild budget for widthCount \(widthCount).",
                file: file,
                line: line
            )
            return
        }

        XCTAssertLessThanOrEqual(
            widthSweep.avg,
            avgBudget,
            """
            Prepared-content relayout regression: solve(width-sweep)(large) avg \(fmt(widthSweep.avg)) \
            exceeded 60% of solve(rebuild-sweep)(large) avg \(fmt(rebuildSweep.avg)) \
            across \(widthCount) widths (budget \(fmt(avgBudget))).
            """,
            file: file,
            line: line
        )

        XCTAssertLessThanOrEqual(
            widthSweep.p95,
            p95Budget,
            """
            Prepared-content relayout regression: solve(width-sweep)(large) p95 \(fmt(widthSweep.p95)) \
            exceeded 60% of solve(rebuild-sweep)(large) p95 \(fmt(rebuildSweep.p95)) \
            across \(widthCount) widths (budget \(fmt(p95Budget))).
            """,
            file: file,
            line: line
        )
    }

    static func assertCacheModes(
        results: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lookup = Dictionary(uniqueKeysWithValues: results.map { (key(for: $0), $0) })
        guard
            let cold = lookup["solve(cold-large)(medium)"],
            let warm = lookup["solve(warm-large)(medium)"],
            let thrash = lookup["solve(tiny-thrash)(medium)"]
        else {
            XCTFail("Missing cache mode entries for benchmark regression checks", file: file, line: line)
            return
        }

        if let baseline = BenchmarkBaselineLoader.load(file: file, line: line) {
            for (keyName, measured) in [
                ("solve(cold-large)(medium)", cold),
                ("solve(warm-large)(medium)", warm),
                ("solve(tiny-thrash)(medium)", thrash)
            ] {
                assertHarnessMatches(measured, key: keyName, baseline: baseline, file: file, line: line)
            }
        }

        XCTAssertLessThan(
            warm.avg,
            cold.avg,
            "Expected warm cache mode to be faster than cold mode",
            file: file,
            line: line
        )

        XCTAssertLessThan(
            warm.avg,
            thrash.avg,
            "Expected warm cache mode to be faster than eviction-thrash mode",
            file: file,
            line: line
        )
    }

    /// Asserts that every guarded baseline key in `group` was measured, that no
    /// measured result belonging to the group's label family is missing a baseline
    /// entry, and that measured results are within budget for the ones that match on
    /// both sides. Measured results outside the guarded label family (e.g. isolated
    /// arithmetic/TextKit measurements mixed into `layoutResults`) are intentionally
    /// left alone.
    private static func assertGroup(
        _ results: [BenchmarkResult],
        group: BenchmarkBaselineGroup,
        baseline: BenchmarkBaseline,
        isGuardedFamily: (BenchmarkResult) -> Bool,
        file: StaticString,
        line: UInt
    ) {
        let expected = Dictionary(
            uniqueKeysWithValues: baseline.measurements(in: group).map { ($0.key, $0) }
        )
        let measuredByKey = Dictionary(uniqueKeysWithValues: results.map { (key(for: $0), $0) })
        let guardedMeasuredKeys = Set(results.filter(isGuardedFamily).map(key(for:)))
        let expectedKeys = Set(expected.keys)

        for missingKey in expectedKeys.subtracting(guardedMeasuredKeys).sorted() {
            XCTFail(
                "Missing measured benchmark result for \(missingKey) [group \(group.rawValue), baseline \(baseline.version)]",
                file: file,
                line: line
            )
        }

        for unexpectedKey in guardedMeasuredKeys.subtracting(expectedKeys).sorted() {
            XCTFail(
                "Measured guarded result \(unexpectedKey) has no baseline entry in group \(group.rawValue) [baseline \(baseline.version)]",
                file: file,
                line: line
            )
        }

        for keyName in expectedKeys.intersection(guardedMeasuredKeys).sorted() {
            guard let measured = measuredByKey[keyName], let baselineMeasurement = expected[keyName] else { continue }

            assertHarnessMatches(measured, key: keyName, baseline: baseline, file: file, line: line)

            guard baselineMeasurement.enforceAverageBudget else { continue }

            let baselineAvg = baselineMeasurement.averageMilliseconds
            let budget = max(
                baselineAvg * baseline.policy.maxSlowdownFactor,
                baselineAvg + baseline.policy.absoluteSlackMilliseconds
            )

            XCTAssertLessThanOrEqual(
                measured.avg,
                budget,
                """
                Benchmark regression for \(keyName): avg \(fmt(measured.avg)) exceeded budget \(fmt(budget)) \
                (baseline \(fmt(baselineAvg)), version \(baseline.version))
                """,
                file: file,
                line: line
            )
        }
    }

    private static func assertWarmCacheImproves(
        _ results: [BenchmarkResult],
        file: StaticString,
        line: UInt
    ) {
        let lookup = Dictionary(uniqueKeysWithValues: results.map { (key(for: $0), $0) })
        guard
            let cold = lookup["solve(cold)(medium)"],
            let warm = lookup["solve(warm)(medium)"]
        else {
            XCTFail("Missing cold/warm cache entries for baseline comparison", file: file, line: line)
            return
        }

        XCTAssertLessThan(
            warm.avg,
            cold.avg,
            "Warm cache benchmark should be faster than cold cache benchmark",
            file: file,
            line: line
        )
    }

    private static func assertConcurrencyIsNotSlower(
        _ results: [BenchmarkResult],
        file: StaticString,
        line: UInt
    ) {
        let lookup = Dictionary(uniqueKeysWithValues: results.map { (key(for: $0), $0) })

        if let sequential4 = lookup["sequential-4x(medium)"],
           let concurrent4 = lookup["concurrent-4x(medium)"] {
            XCTAssertLessThanOrEqual(
                concurrent4.avg,
                sequential4.avg,
                "4-way concurrent benchmark should not be slower than sequential",
                file: file,
                line: line
            )
        } else {
            XCTFail("Missing 4x concurrency results", file: file, line: line)
        }

        if let sequential8 = lookup["sequential-8x(large)"],
           let concurrent8 = lookup["concurrent-8x(large)"] {
            XCTAssertLessThanOrEqual(
                concurrent8.avg,
                sequential8.avg,
                "8-way concurrent benchmark should not be slower than sequential",
                file: file,
                line: line
            )
        }
    }

    static func preparedContentRelayoutBudget(rebuildMetric: Double, widthCount: Int) -> Double? {
        guard widthCount > 1 else { return nil }
        return rebuildMetric * preparedContentRelayoutBudgetRatio
    }

    /// Verifies a measured result was produced with the exact warmup/measure
    /// iteration counts recorded in `baseline.harness`, so baseline metadata can
    /// never silently drift from the workload it claims to describe.
    private static func assertHarnessMatches(
        _ result: BenchmarkResult,
        key keyName: String,
        baseline: BenchmarkBaseline,
        file: StaticString,
        line: UInt
    ) {
        if result.warmupIterations != baseline.harness.warmupIterations {
            XCTFail(
                """
                Benchmark harness drift for \(keyName): warmupIterations \(result.warmupIterations) != \
                expected \(baseline.harness.warmupIterations) (baseline \(baseline.version))
                """,
                file: file,
                line: line
            )
        }

        if result.iterations != baseline.harness.measureIterations {
            XCTFail(
                """
                Benchmark harness drift for \(keyName): measured iterations \(result.iterations) != \
                expected \(baseline.harness.measureIterations) (baseline \(baseline.version))
                """,
                file: file,
                line: line
            )
        }
    }

    private static func key(for result: BenchmarkResult) -> String {
        result.fixture.isEmpty ? result.label : "\(result.label)(\(result.fixture))"
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.3fms", value)
    }
}
