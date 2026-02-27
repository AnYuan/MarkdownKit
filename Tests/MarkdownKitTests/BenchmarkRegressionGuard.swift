import Foundation
import XCTest

/// Regression guardrails for benchmark tests.
/// Baseline source: docs/BENCHMARK_BASELINE.md (2026-02-27, commit 123c77b+local).
enum BenchmarkRegressionGuard {

    static let baselineVersion = "2026-02-27@123c77b+local"
    static let maxSlowdownFactor: Double = 3.0
    static let absoluteSlackMs: Double = 5.0

    private static let avgMsBaseline: [String: Double] = [
        "parse(small)": 0.244,
        "parse(medium)": 1.61,
        "parse(large)": 13.17,
        "parse(code-heavy)": 0.266,
        "parse(table-heavy)": 13.24,
        "parse(math-heavy)": 0.565,
        "parse(details-heavy)": 2.19,
        "parse(diagram-heavy)": 0.308,
        "parse(tasklist-heavy)": 7.01,
        "solve(small)": 0.786,
        "solve(medium)": 231.5,
        "solve(large)": 34.60,
        "solve(code-heavy)": 16.85,
        "solve(table-heavy)": 18.87,
        "solve(math-heavy)": 72.07,
        "solve(details-heavy)": 1.86,
        "solve(diagram-heavy)": 6.13,
        "solve(tasklist-heavy)": 7.38,
        "solve(cold)(medium)": 228.1,
        "solve(warm)(medium)": 0.006,
        "sequential-4x(medium)": 943.0,
        "concurrent-4x(medium)": 237.5,
        "sequential-8x(large)": 333.8,
        "concurrent-8x(large)": 105.7
    ]

    static func assertCoreReport(
        parseResults: [BenchmarkResult],
        layoutResults: [BenchmarkResult],
        cacheResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAgainstBaselines(parseResults, keys: [
            "parse(small)",
            "parse(medium)",
            "parse(large)",
            "parse(code-heavy)",
            "parse(table-heavy)",
            "parse(math-heavy)",
            "parse(details-heavy)",
            "parse(diagram-heavy)",
            "parse(tasklist-heavy)"
        ], file: file, line: line)

        assertAgainstBaselines(layoutResults, keys: [
            "solve(small)",
            "solve(medium)",
            "solve(large)",
            "solve(code-heavy)",
            "solve(table-heavy)",
            "solve(math-heavy)",
            "solve(details-heavy)",
            "solve(diagram-heavy)",
            "solve(tasklist-heavy)"
        ], file: file, line: line)

        assertAgainstBaselines(cacheResults, keys: [
            "solve(cold)(medium)",
            "solve(warm)(medium)"
        ], file: file, line: line)

        assertWarmCacheDominatesCold(cacheResults, file: file, line: line)
    }

    static func assertDeepReport(
        concurrencyResults: [BenchmarkResult],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertAgainstBaselines(concurrencyResults, keys: [
            "sequential-4x(medium)",
            "concurrent-4x(medium)",
            "sequential-8x(large)",
            "concurrent-8x(large)"
        ], file: file, line: line)
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

    private static func assertAgainstBaselines(
        _ results: [BenchmarkResult],
        keys: [String],
        file: StaticString,
        line: UInt
    ) {
        let lookup = Dictionary(uniqueKeysWithValues: results.map { (key(for: $0), $0) })

        for keyName in keys {
            guard let baseline = avgMsBaseline[keyName] else {
                XCTFail("Missing baseline for \(keyName) [\(baselineVersion)]", file: file, line: line)
                continue
            }
            guard let measured = lookup[keyName] else {
                XCTFail("Missing measured benchmark result for \(keyName)", file: file, line: line)
                continue
            }

            let budget = max(
                baseline * maxSlowdownFactor,
                baseline + absoluteSlackMs
            )

            XCTAssertLessThanOrEqual(
                measured.avg,
                budget,
                """
                Benchmark regression for \(keyName): avg \(fmt(measured.avg)) exceeded budget \(fmt(budget)) \
                (baseline \(fmt(baseline)), version \(baselineVersion))
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

    private static func key(for result: BenchmarkResult) -> String {
        result.fixture.isEmpty ? result.label : "\(result.label)(\(result.fixture))"
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.3fms", value)
    }
}
