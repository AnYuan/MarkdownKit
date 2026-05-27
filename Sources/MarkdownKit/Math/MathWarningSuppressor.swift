//
//  MathWarningSuppressor.swift
//  MarkdownKit
//
//  Actor-isolated LRU set that deduplicates MathJax error messages so a
//  pathological document doesn't spam the unified log with the same warning
//  hundreds of times.
//

import Foundation

actor MathWarningSuppressor {
    static let defaultCapacity = 128

    private var seenMessages: Set<String> = []
    private var insertionOrder: [String] = []
    private let capacity: Int

    init(capacity: Int = MathWarningSuppressor.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    func shouldLog(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if seenMessages.contains(normalized) { return false }

        // Evict oldest entry when at capacity
        if seenMessages.count >= capacity {
            let oldest = insertionOrder.removeFirst()
            seenMessages.remove(oldest)
        }

        seenMessages.insert(normalized)
        insertionOrder.append(normalized)
        return true
    }

    /// Current number of tracked messages. Exposed for testing.
    var count: Int { seenMessages.count }
}
