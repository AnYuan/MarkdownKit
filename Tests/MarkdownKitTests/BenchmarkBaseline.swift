import Foundation
import XCTest

/// The guarded measurement group families in `benchmark_baseline.json`.
///
/// Each group corresponds to one array of `BenchmarkResult` values produced by a
/// specific benchmark test method. Keeping the group identifiers here (rather than
/// as free-form strings scattered through the guard) is what lets
/// `BenchmarkBaseline.validationErrors()` reject unsupported groups and lets the
/// guard require every group to be present without hard-coding key lists.
enum BenchmarkBaselineGroup: String, Decodable, CaseIterable {
    case coreParse = "core.parse"
    case coreLayout = "core.layout"
    case coreCache = "core.cache"
    case deepConcurrency = "deep.concurrency"
    case coordinatorStreaming = "coordinator.streaming"
}

/// One guarded timing entry: a unique key, the group it belongs to, and the
/// recorded average duration in milliseconds.
///
/// `enforceAverageBudget` may be omitted from the JSON, which means `true`.
/// Explicit `null` is invalid. The field lets a measurement stay measured and
/// group/key-contract-covered while being exempted from the absolute average
/// regression budget when a relational contract (e.g.
/// `assertWarmCacheImproves`) is the more meaningful guard for that workload
/// (see `solve(warm)(medium)`).
struct BenchmarkBaselineMeasurement: Decodable {
    let key: String
    let group: String
    let averageMilliseconds: Double
    let enforceAverageBudget: Bool

    private enum CodingKeys: String, CodingKey {
        case key
        case group
        case averageMilliseconds
        case enforceAverageBudget
    }

    init(key: String, group: String, averageMilliseconds: Double, enforceAverageBudget: Bool = true) {
        self.key = key
        self.group = group
        self.averageMilliseconds = averageMilliseconds
        self.enforceAverageBudget = enforceAverageBudget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        group = try container.decode(String.self, forKey: .group)
        averageMilliseconds = try container.decode(Double.self, forKey: .averageMilliseconds)
        if container.contains(.enforceAverageBudget) {
            enforceAverageBudget = try container.decode(Bool.self, forKey: .enforceAverageBudget)
        } else {
            enforceAverageBudget = true
        }
    }
}

struct BenchmarkBaselinePlatform: Decodable {
    let os: String
    let arch: String
    let device: String
}

struct BenchmarkBaselineHarness: Decodable {
    let warmupIterations: Int
    let measureIterations: Int
    let clock: String

    /// Number of independent, isolated-process recording runs the baseline
    /// values were aggregated from. Required so the recording contract (one
    /// isolated Release process per canonical workload, repeated
    /// `independentRuns` times) is explicit in the schema rather than implied.
    let independentRuns: Int

    /// Human-readable description of how `averageMilliseconds` was derived
    /// from the `independentRuns` per-process averages (e.g. "median of
    /// per-process averages").
    let aggregation: String
}

struct BenchmarkBaselinePolicy: Decodable {
    let maxSlowdownFactor: Double
    let absoluteSlackMilliseconds: Double
}

/// Decoded, schema-validated contents of `Fixtures/benchmark_baseline.json`.
///
/// This is the single source of truth for benchmark regression budgets. Both
/// `BenchmarkRegressionGuard` (enforcement inside `swift test`) and
/// `scripts/render_benchmark_baseline.py` (generated documentation) read the same
/// JSON file so the numbers and policy can never drift apart.
struct BenchmarkBaseline: Decodable {
    static let supportedSchemaVersion = 2

    /// The only measurement key allowed to disable `enforceAverageBudget`. The
    /// warm-cache workload's regression coverage comes from the relational
    /// `assertWarmCacheImproves` contract (warm < cold), not an absolute
    /// millisecond budget, because sub-millisecond cache hits are dominated by
    /// clock-resolution noise rather than real regressions.
    static let averageBudgetExemptKey = "solve(warm)(medium)"

    let schemaVersion: Int
    let version: String
    let recordedAt: String
    let commit: String
    let platform: BenchmarkBaselinePlatform
    let harness: BenchmarkBaselineHarness
    let policy: BenchmarkBaselinePolicy
    let measurements: [BenchmarkBaselineMeasurement]

    /// Every guarded measurement belonging to a given group, in file order.
    func measurements(in group: BenchmarkBaselineGroup) -> [BenchmarkBaselineMeasurement] {
        measurements.filter { $0.group == group.rawValue }
    }

    /// Structural validation of the decoded document. Returns a description for
    /// every problem found; an empty result means the baseline is safe to use.
    func validationErrors() -> [String] {
        var errors: [String] = []

        /// Mirrors `render_benchmark_baseline.py`'s Markdown-safety contract so
        /// both consumers accept/reject the same schema: fields rendered into
        /// generated Markdown must be a single line (no control characters,
        /// which could inject extra headings/table rows) and must not contain
        /// characters that would corrupt the specific construct they're
        /// embedded in (a backtick inside a code span, a pipe inside a table
        /// cell).
        func checkMarkdownSafe(_ value: String, field: String, forbidding forbidden: String = "") {
            if value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
                errors.append("\(field) must be a single line with no control characters.")
            }
            for character in forbidden where value.contains(character) {
                errors.append("\(field) must not contain the '\(character)' character.")
            }
        }

        if schemaVersion != Self.supportedSchemaVersion {
            errors.append("Unsupported schemaVersion \(schemaVersion); expected \(Self.supportedSchemaVersion).")
        }
        if version.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("version must not be empty.")
        }
        checkMarkdownSafe(version, field: "version", forbidding: "`")
        if recordedAt.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("recordedAt must not be empty.")
        }
        checkMarkdownSafe(recordedAt, field: "recordedAt")
        if commit.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("commit must not be empty.")
        }
        checkMarkdownSafe(commit, field: "commit", forbidding: "`")
        if platform.os.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("platform.os must not be empty.")
        }
        checkMarkdownSafe(platform.os, field: "platform.os")
        if platform.arch.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("platform.arch must not be empty.")
        }
        checkMarkdownSafe(platform.arch, field: "platform.arch")
        if platform.device.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("platform.device must not be empty.")
        }
        checkMarkdownSafe(platform.device, field: "platform.device")
        if harness.warmupIterations <= 0 {
            errors.append("harness.warmupIterations must be positive.")
        }
        if harness.measureIterations <= 0 {
            errors.append("harness.measureIterations must be positive.")
        }
        if harness.clock.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("harness.clock must not be empty.")
        }
        checkMarkdownSafe(harness.clock, field: "harness.clock", forbidding: "`")
        if harness.independentRuns <= 0 {
            errors.append("harness.independentRuns must be positive.")
        }
        if harness.aggregation.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("harness.aggregation must not be empty.")
        }
        checkMarkdownSafe(harness.aggregation, field: "harness.aggregation", forbidding: "`")
        if !(policy.maxSlowdownFactor.isFinite && policy.maxSlowdownFactor > 0) {
            errors.append("policy.maxSlowdownFactor must be a positive, finite number.")
        }
        if !(policy.absoluteSlackMilliseconds.isFinite && policy.absoluteSlackMilliseconds > 0) {
            errors.append("policy.absoluteSlackMilliseconds must be a positive, finite number.")
        }

        var seenKeys = Set<String>()
        for measurement in measurements {
            if measurement.key.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("Measurement key must not be empty.")
            }
            checkMarkdownSafe(measurement.key, field: "Measurement key '\(measurement.key)'", forbidding: "`|")
            if !seenKeys.insert(measurement.key).inserted {
                errors.append("Duplicate measurement key '\(measurement.key)'.")
            }
            if BenchmarkBaselineGroup(rawValue: measurement.group) == nil {
                errors.append("Measurement '\(measurement.key)' has unsupported group '\(measurement.group)'.")
            }
            if !(measurement.averageMilliseconds.isFinite && measurement.averageMilliseconds > 0) {
                errors.append("Measurement '\(measurement.key)' must have a positive, finite averageMilliseconds.")
            }
        }

        let presentGroups = Set(measurements.compactMap { BenchmarkBaselineGroup(rawValue: $0.group) })
        for requiredGroup in BenchmarkBaselineGroup.allCases where !presentGroups.contains(requiredGroup) {
            errors.append("Missing required group '\(requiredGroup.rawValue)'.")
        }

        // The average budget exemption is a narrow, explicit carve-out for the
        // warm-cache workload (whose enforcement is the relational
        // `assertWarmCacheImproves` contract, not an absolute budget). Any other
        // key opting out would silently weaken regression coverage, so it is
        // rejected here rather than left to reviewer vigilance.
        let exemptKeys = measurements.filter { !$0.enforceAverageBudget }.map(\.key)
        for exemptKey in exemptKeys where exemptKey != Self.averageBudgetExemptKey {
            errors.append(
                "Measurement '\(exemptKey)' disables enforceAverageBudget, but only "
                + "'\(Self.averageBudgetExemptKey)' is permitted to be average-budget-exempt."
            )
        }

        return errors
    }
}

/// Loads and validates `BenchmarkBaseline` from the test bundle's `Fixtures`
/// resources, reporting any failure as an explicit `XCTFail` instead of silently
/// falling back to embedded defaults.
enum BenchmarkBaselineLoader {
    static func load(file: StaticString = #filePath, line: UInt = #line) -> BenchmarkBaseline? {
        guard let url = Bundle.module.url(
            forResource: "benchmark_baseline",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("Could not find benchmark_baseline.json in test bundle resources.", file: file, line: line)
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            XCTFail("Failed to read benchmark_baseline.json: \(error)", file: file, line: line)
            return nil
        }

        let baseline: BenchmarkBaseline
        do {
            baseline = try JSONDecoder().decode(BenchmarkBaseline.self, from: data)
        } catch {
            XCTFail("Failed to decode benchmark_baseline.json: \(error)", file: file, line: line)
            return nil
        }

        let errors = baseline.validationErrors()
        if !errors.isEmpty {
            XCTFail(
                "benchmark_baseline.json failed schema validation:\n" + errors.map { "- \($0)" }.joined(separator: "\n"),
                file: file,
                line: line
            )
            return nil
        }

        return baseline
    }
}
