import Foundation
import XCTest
@testable import MarkdownKit

/// Fast, non-timing correctness tests for the benchmark baseline contract.
///
/// Deliberately excluded from `scripts/verify_benchmarks.sh` (which owns actual
/// timing runs) and deliberately does NOT contain "Benchmark" in its name so
/// `scripts/verify_fast.sh`'s `*Benchmark*` suite exclusion does not skip it.
/// These tests only decode/validate JSON and compare key sets — no benchmark
/// workload is ever executed here.
final class PerformanceBaselineContractTests: XCTestCase {

    func testBaselineLoadsAndPassesSchemaValidation() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        XCTAssertEqual(baseline.schemaVersion, BenchmarkBaseline.supportedSchemaVersion)
        XCTAssertTrue(
            baseline.validationErrors().isEmpty,
            "Unexpected validation errors: \(baseline.validationErrors())"
        )
        XCTAssertFalse(baseline.measurements.isEmpty)
    }

    func testCoreParseGroupMatchesFixtureKeysExactly() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        let expectedKeys = Set(BenchmarkFixtures.allFixtures.map { "parse(\($0.name))" })
        let actualKeys = Set(baseline.measurements(in: .coreParse).map(\.key))
        XCTAssertEqual(actualKeys, expectedKeys)
    }

    func testCoreLayoutGroupMatchesFixtureKeysExactly() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        let expectedKeys = Set(BenchmarkFixtures.allFixtures.map { "solve(\($0.name))" })
        let actualKeys = Set(baseline.measurements(in: .coreLayout).map(\.key))
        XCTAssertEqual(actualKeys, expectedKeys)
    }

    func testCoreCacheGroupMatchesKnownKeysExactly() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        let expectedKeys: Set<String> = ["solve(cold)(medium)", "solve(warm)(medium)"]
        let actualKeys = Set(baseline.measurements(in: .coreCache).map(\.key))
        XCTAssertEqual(actualKeys, expectedKeys)

        let exemptKeys = Set(baseline.measurements.filter { !$0.enforceAverageBudget }.map(\.key))
        XCTAssertEqual(exemptKeys, [BenchmarkBaseline.averageBudgetExemptKey])

        let warmCache = try XCTUnwrap(
            baseline.measurements.first { $0.key == BenchmarkBaseline.averageBudgetExemptKey }
        )
        XCTAssertFalse(warmCache.enforceAverageBudget)
        XCTAssertEqual(warmCache.group, BenchmarkBaselineGroup.coreCache.rawValue)

        for measurement in baseline.measurements where measurement.key != BenchmarkBaseline.averageBudgetExemptKey {
            XCTAssertTrue(
                measurement.enforceAverageBudget,
                "Expected \(measurement.key) to have its average budget enforced"
            )
        }
    }

    func testDeepConcurrencyAndCoordinatorGroupsMatchKnownKeysExactly() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        let expectedConcurrencyKeys: Set<String> = [
            "sequential-4x(medium)",
            "concurrent-4x(medium)",
            "sequential-8x(large)",
            "concurrent-8x(large)"
        ]
        let actualConcurrencyKeys = Set(baseline.measurements(in: .deepConcurrency).map(\.key))
        XCTAssertEqual(actualConcurrencyKeys, expectedConcurrencyKeys)

        let expectedCoordinatorKeys: Set<String> = ["latest-settled(large-3-updates)"]
        let actualCoordinatorKeys = Set(baseline.measurements(in: .coordinatorStreaming).map(\.key))
        XCTAssertEqual(actualCoordinatorKeys, expectedCoordinatorKeys)
    }

    func testMeasurementKeysAreGloballyUnique() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        let keys = baseline.measurements.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count, "Duplicate measurement keys detected")
    }

    func testEveryRequiredGroupIsPresent() throws {
        let baseline = try XCTUnwrap(BenchmarkBaselineLoader.load())
        let presentGroups = Set(baseline.measurements.map(\.group))
        for group in BenchmarkBaselineGroup.allCases {
            XCTAssertTrue(presentGroups.contains(group.rawValue), "Missing required group \(group.rawValue)")
        }
    }

    func testMalformedBaselineFailsValidation() {
        let malformed = BenchmarkBaseline(
            schemaVersion: 999,
            version: "",
            recordedAt: "",
            commit: "",
            platform: BenchmarkBaselinePlatform(os: "", arch: "", device: ""),
            harness: BenchmarkBaselineHarness(
                warmupIterations: 0,
                measureIterations: 0,
                clock: "",
                independentRuns: 0,
                aggregation: ""
            ),
            policy: BenchmarkBaselinePolicy(maxSlowdownFactor: 0, absoluteSlackMilliseconds: 0),
            measurements: [
                BenchmarkBaselineMeasurement(key: "dup", group: "core.parse", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(key: "dup", group: "core.parse", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(key: "bad-group", group: "not.a.group", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(key: "non-positive", group: "core.layout", averageMilliseconds: 0),
                BenchmarkBaselineMeasurement(key: "   ", group: "core.layout", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(
                    key: "wrongly-exempt",
                    group: "core.layout",
                    averageMilliseconds: 1,
                    enforceAverageBudget: false
                )
            ]
        )

        let errors = malformed.validationErrors()

        // schemaVersion
        XCTAssertTrue(errors.contains { $0.contains("schemaVersion") })
        // top-level string fields
        XCTAssertTrue(errors.contains { $0.contains("version must not be empty") })
        XCTAssertTrue(errors.contains { $0.contains("recordedAt must not be empty") })
        XCTAssertTrue(errors.contains { $0.contains("commit must not be empty") })
        // platform fields
        XCTAssertTrue(errors.contains { $0.contains("platform.os must not be empty") })
        XCTAssertTrue(errors.contains { $0.contains("platform.arch must not be empty") })
        XCTAssertTrue(errors.contains { $0.contains("platform.device must not be empty") })
        // harness fields
        XCTAssertTrue(errors.contains { $0.contains("harness.warmupIterations must be positive") })
        XCTAssertTrue(errors.contains { $0.contains("harness.measureIterations must be positive") })
        XCTAssertTrue(errors.contains { $0.contains("harness.clock must not be empty") })
        XCTAssertTrue(errors.contains { $0.contains("harness.independentRuns must be positive") })
        XCTAssertTrue(errors.contains { $0.contains("harness.aggregation must not be empty") })
        // policy fields
        XCTAssertTrue(errors.contains { $0.contains("policy.maxSlowdownFactor") && $0.contains("positive, finite") })
        XCTAssertTrue(errors.contains { $0.contains("policy.absoluteSlackMilliseconds") && $0.contains("positive, finite") })
        // measurement-level checks
        XCTAssertTrue(errors.contains { $0.contains("Measurement key must not be empty") })
        XCTAssertTrue(errors.contains { $0.contains("Duplicate measurement key") })
        XCTAssertTrue(errors.contains { $0.contains("unsupported group") })
        XCTAssertTrue(errors.contains { $0.contains("must have a positive, finite averageMilliseconds") })
        // required-group coverage
        XCTAssertTrue(errors.contains { $0.contains("Missing required group") })
        // average-budget exemption scoping
        XCTAssertTrue(errors.contains { $0.contains("wrongly-exempt") && $0.contains("average-budget-exempt") })

        let nullBudgetJSON = Data(
            """
            {
              "key": "solve(warm)(medium)",
              "group": "core.cache",
              "averageMilliseconds": 0.001,
              "enforceAverageBudget": null
            }
            """.utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(BenchmarkBaselineMeasurement.self, from: nullBudgetJSON))
    }

    /// A fully schema-valid baseline builder used to isolate one field at a time
    /// so non-finite-value assertions don't become brittle to unrelated errors.
    private func makeValidBaseline(
        maxSlowdownFactor: Double = 2,
        absoluteSlackMilliseconds: Double = 2,
        firstAverageMilliseconds: Double = 1
    ) -> BenchmarkBaseline {
        BenchmarkBaseline(
            schemaVersion: BenchmarkBaseline.supportedSchemaVersion,
            version: "v1",
            recordedAt: "2026-01-01",
            commit: "abc123",
            platform: BenchmarkBaselinePlatform(os: "macOS", arch: "arm64", device: "Apple Silicon"),
            harness: BenchmarkBaselineHarness(
                warmupIterations: 3,
                measureIterations: 20,
                clock: "mach_absolute_time",
                independentRuns: 5,
                aggregation: "median of per-process averages"
            ),
            policy: BenchmarkBaselinePolicy(
                maxSlowdownFactor: maxSlowdownFactor,
                absoluteSlackMilliseconds: absoluteSlackMilliseconds
            ),
            measurements: [
                BenchmarkBaselineMeasurement(key: "parse(small)", group: "core.parse", averageMilliseconds: firstAverageMilliseconds),
                BenchmarkBaselineMeasurement(key: "solve(small)", group: "core.layout", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(key: "solve(cold)(medium)", group: "core.cache", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(key: "sequential-4x(medium)", group: "deep.concurrency", averageMilliseconds: 1),
                BenchmarkBaselineMeasurement(key: "latest-settled(large-3-updates)", group: "coordinator.streaming", averageMilliseconds: 1)
            ]
        )
    }

    func testNonFinitePolicyValueFailsValidation() {
        let baseline = makeValidBaseline(maxSlowdownFactor: .infinity)
        let errors = baseline.validationErrors()
        XCTAssertEqual(errors.count, 1, "Expected only the finiteness error, found: \(errors)")
        XCTAssertTrue(errors.contains { $0.contains("policy.maxSlowdownFactor") && $0.contains("finite") })
    }

    func testNonFiniteMeasurementAverageFailsValidation() {
        let baseline = makeValidBaseline(firstAverageMilliseconds: .nan)
        let errors = baseline.validationErrors()
        XCTAssertEqual(errors.count, 1, "Expected only the finiteness error, found: \(errors)")
        XCTAssertTrue(errors.contains { $0.contains("parse(small)") && $0.contains("finite") })
    }
}
