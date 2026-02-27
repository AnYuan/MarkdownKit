import Foundation
import Darwin.Mach

/// Result of a benchmark run containing timing and memory statistics.
struct BenchmarkResult: Sendable {
    let label: String
    let fixture: String
    let iterations: Int
    let warmupIterations: Int

    // Timing (milliseconds)
    let timings: [Double]
    let avg: Double
    let min: Double
    let max: Double
    let p50: Double
    let p95: Double

    // Memory (bytes)
    let peakMemoryDelta: Int64
    let avgMemoryDelta: Int64
}

/// Engine that runs a closure multiple times with warmup, capturing timing + memory stats.
struct BenchmarkHarness {

    let warmupIterations: Int
    let measureIterations: Int

    init(warmup: Int = 3, iterations: Int = 20) {
        self.warmupIterations = warmup
        self.measureIterations = iterations
    }

    // MARK: - Synchronous measurement

    func measure(
        label: String,
        fixture: String = "",
        operation: () -> Void
    ) -> BenchmarkResult {
        for _ in 0..<warmupIterations {
            operation()
        }

        var timings: [Double] = []
        timings.reserveCapacity(measureIterations)
        var memoryDeltas: [Int64] = []
        memoryDeltas.reserveCapacity(measureIterations)

        for _ in 0..<measureIterations {
            let memBefore = currentResidentSize()
            let start = mach_absolute_time()

            operation()

            let end = mach_absolute_time()
            let memAfter = currentResidentSize()

            timings.append(machToMilliseconds(end - start))
            memoryDeltas.append(Swift.max(0, memAfter - memBefore))
        }

        return buildResult(label: label, fixture: fixture, timings: timings, memoryDeltas: memoryDeltas)
    }

    // MARK: - Async measurement

    func measureAsync(
        label: String,
        fixture: String = "",
        operation: () async -> Void
    ) async -> BenchmarkResult {
        for _ in 0..<warmupIterations {
            await operation()
        }

        var timings: [Double] = []
        timings.reserveCapacity(measureIterations)
        var memoryDeltas: [Int64] = []
        memoryDeltas.reserveCapacity(measureIterations)

        for _ in 0..<measureIterations {
            let memBefore = currentResidentSize()
            let start = mach_absolute_time()

            await operation()

            let end = mach_absolute_time()
            let memAfter = currentResidentSize()

            timings.append(machToMilliseconds(end - start))
            memoryDeltas.append(Swift.max(0, memAfter - memBefore))
        }

        return buildResult(label: label, fixture: fixture, timings: timings, memoryDeltas: memoryDeltas)
    }

    // MARK: - Mach time conversion

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private func machToMilliseconds(_ elapsed: UInt64) -> Double {
        let info = Self.timebaseInfo
        let nanos = Double(elapsed) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000.0
    }

    // MARK: - Memory via mach_task_basic_info

    private func currentResidentSize() -> Int64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }

    // MARK: - Statistics

    private func buildResult(
        label: String,
        fixture: String,
        timings: [Double],
        memoryDeltas: [Int64]
    ) -> BenchmarkResult {
        let sorted = timings.sorted()
        let avg = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)

        let peakMem = memoryDeltas.max() ?? 0
        let avgMem = memoryDeltas.isEmpty ? 0 :
            memoryDeltas.reduce(Int64(0), +) / Int64(memoryDeltas.count)

        return BenchmarkResult(
            label: label,
            fixture: fixture,
            iterations: measureIterations,
            warmupIterations: warmupIterations,
            timings: timings,
            avg: avg,
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            p50: p50,
            p95: p95,
            peakMemoryDelta: peakMem,
            avgMemoryDelta: avgMem
        )
    }

    private func percentile(_ sorted: [Double], _ pct: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Double(sorted.count - 1) * pct
        let lower = Int(index.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }
}
