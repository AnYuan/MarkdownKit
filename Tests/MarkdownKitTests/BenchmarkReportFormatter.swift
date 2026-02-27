import Foundation

struct BenchmarkReportFormatter {

    /// Prints a formatted benchmark report table to stdout.
    static func printReport(
        parseResults: [BenchmarkResult],
        layoutResults: [BenchmarkResult],
        cacheResults: [BenchmarkResult]
    ) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }()

        let platform: String = {
            #if os(macOS)
            return "macOS"
            #elseif os(iOS)
            return "iOS"
            #else
            return "unknown"
            #endif
        }()

        let totalWidth = 78

        print("")
        printBorder(totalWidth)
        printCentered("MarkdownKit Benchmark Report", width: totalWidth)
        printCentered("\(dateStr) · \(platform) · \(arch)", width: totalWidth)
        printBorder(totalWidth)

        if !parseResults.isEmpty {
            printPhase("Phase 1: Parse", results: parseResults, totalWidth: totalWidth)
        }

        if !layoutResults.isEmpty {
            printPhase("Phase 2: Layout", results: layoutResults, totalWidth: totalWidth)
        }

        if !cacheResults.isEmpty {
            printPhase("Cache Statistics", results: cacheResults, totalWidth: totalWidth)
        }

        printBorder(totalWidth)
        print("")
    }

    // MARK: - Internal

    private static let opWidth = 32
    private static let numWidth = 9
    private static let memWidth = 9

    private static func printPhase(_ title: String, results: [BenchmarkResult], totalWidth: Int) {
        print("+" + String(repeating: "-", count: totalWidth) + "+")
        printCentered(title, width: totalWidth)
        print("+" + String(repeating: "-", count: totalWidth) + "+")

        let header = "| "
            + pad("Operation", opWidth)
            + " | " + pad("Avg", numWidth)
            + " | " + pad("P50", numWidth)
            + " | " + pad("P95", numWidth)
            + " | " + pad("Max", numWidth)
            + " | " + pad("Mem", memWidth)
            + " |"
        print(header)

        let sep = "|-"
            + String(repeating: "-", count: opWidth)
            + "-|-" + String(repeating: "-", count: numWidth)
            + "-|-" + String(repeating: "-", count: numWidth)
            + "-|-" + String(repeating: "-", count: numWidth)
            + "-|-" + String(repeating: "-", count: numWidth)
            + "-|-" + String(repeating: "-", count: memWidth)
            + "-|"
        print(sep)

        for result in results {
            let label: String
            if result.fixture.isEmpty {
                label = result.label
            } else {
                label = "\(result.label)(\(result.fixture))"
            }

            let row = "| "
                + pad(label, opWidth)
                + " | " + pad(fmtMs(result.avg), numWidth)
                + " | " + pad(fmtMs(result.p50), numWidth)
                + " | " + pad(fmtMs(result.p95), numWidth)
                + " | " + pad(fmtMs(result.max), numWidth)
                + " | " + pad(fmtBytes(result.peakMemoryDelta), memWidth)
                + " |"
            print(row)
        }
    }

    // MARK: - Formatting helpers

    private static func fmtMs(_ value: Double) -> String {
        if value < 1.0 {
            return String(format: "%.3fms", value)
        } else if value < 100 {
            return String(format: "%.2fms", value)
        } else {
            return String(format: "%.1fms", value)
        }
    }

    private static func fmtBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "~0" }
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)KB" }
        return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width {
            return String(text.prefix(width))
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    private static func printBorder(_ width: Int) {
        print("+" + String(repeating: "=", count: width) + "+")
    }

    private static func printCentered(_ text: String, width: Int) {
        let totalPad = max(0, width - text.count)
        let left = totalPad / 2
        let right = totalPad - left
        print("|" + String(repeating: " ", count: left) + text + String(repeating: " ", count: right) + "|")
    }
}
