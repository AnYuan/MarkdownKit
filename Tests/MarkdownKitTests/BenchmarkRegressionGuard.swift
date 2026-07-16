import Foundation
import XCTest

/// Regression guardrails for benchmark tests.
///
/// Baseline source: `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json`, the
/// single machine-readable baseline shared with `scripts/render_benchmark_baseline.py`
/// (which renders it into `docs/BENCHMARK_BASELINE.md`). No timing value, policy
/// value, or guarded key list is duplicated in this file — everything is decoded
/// through `BenchmarkBaselineLoader`.
enum BenchmarkRegressionGuard {

    static func assertCoreReport(
        parseResults: [BenchmarkResult],
        layoutResults: [BenchmarkResult],
        cacheResults: [BenchmarkResult],
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

        assertGroup(
            layoutResults,
            group: .coreLayout,
            baseline: baseline,
            isGuardedFamily: { $0.label == "solve" },
            file: file,
            line: line
        )

        assertGroup(
            cacheResults,
            group: .coreCache,
            baseline: baseline,
            isGuardedFamily: { $0.label.hasPrefix("solve(") },
            file: file,
            line: line
        )

        assertWarmCacheDominatesCold(cacheResults, file: file, line: line)
    }

    static func assertDeepReport(
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
    /// entry, and that measured results within budget for the ones that match on
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
            uniqueKeysWithValues: baseline.measurements(in: group).map { ($0.key, $0.averageMilliseconds) }
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
            guard let measured = measuredByKey[keyName], let baselineAvg = expected[keyName] else { continue }

            assertHarnessMatches(measured, key: keyName, baseline: baseline, file: file, line: line)

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

    private static func assertWarmCacheDominatesCold(
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
