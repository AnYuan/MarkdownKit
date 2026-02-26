import Foundation

/// A utility to meticulously measure the performance metrics of the Markdown renderer.
public struct PerformanceProfiler {
    
    public enum Metric: String {
        case astParsing = "AST Parsing"
        case layoutCalculation = "Layout Calculation"
        case viewMounting = "View Mounting"
        case totalRendering = "Total Rendering Time"
    }
    
    /// Executes a block of code, measures the execution time, and logs the result.
    ///
    /// - Parameters:
    ///   - metric: The metric label being measured.
    ///   - log: Whether to print the result to the console automatically.
    ///   - action: The synchronous block of work to measure.
    /// - Returns: The total time elapsed in milliseconds.
    @discardableResult
    public static func measure(_ metric: Metric, log: Bool = true, _ action: () throws -> Void) rethrows -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try action()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let elapsedMilliseconds = (endTime - startTime) * 1000
        
        if log {
            print("[\(metric.rawValue)] Executed in: \(String(format: "%.2f", elapsedMilliseconds)) ms")
        }
        
        return elapsedMilliseconds
    }
    
    /// Executes an asynchronous block of code, measures the execution time, and logs the result.
    @discardableResult
    public static func measureAsync(_ metric: Metric, log: Bool = true, _ action: () async throws -> Void) async rethrows -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try await action()
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let elapsedMilliseconds = (endTime - startTime) * 1000
        
        if log {
            print("[\(metric.rawValue)] Executed in: \(String(format: "%.2f", elapsedMilliseconds)) ms")
        }
        
        return elapsedMilliseconds
    }
}
