import Foundation
import Markdown
import os

/// The main entry point for parsing raw Markdown strings into our high-performance
/// AST, executing any injected middleware plugins along the way.
public struct MarkdownParser {
    
    private static let logger = Logger(subsystem: "com.markdownkit", category: "Parser")

    /// Maximum input size in bytes. Documents exceeding this are rejected with an empty result.
    public static nonisolated(unsafe) var maxInputBytes: Int = 1_048_576 // 1 MB

    /// The plugins that will be executed sequentially on the tree after the initial parse.
    public var plugins: [ASTPlugin]

    public init(plugins: [ASTPlugin] = []) {
        self.plugins = plugins
    }

    /// Parses a raw Markdown string into the `MarkdownKit` AST representation.
    ///
    /// - Parameter text: The raw markdown content.
    /// - Returns: The root `DocumentNode` containing the structured tree.
    ///   Returns an empty document if input exceeds `maxInputBytes`.
    public func parse(_ text: String) -> DocumentNode {
        // Guard against excessively large inputs
        if text.utf8.count > Self.maxInputBytes {
            Self.logger.warning("Input exceeds max size (\(text.utf8.count) bytes > \(Self.maxInputBytes)). Returning empty document.")
            return DocumentNode(range: nil, children: [])
        }

        // Step 1: Parse using Apple's highly-optimized C-backend.
        let document = Document(parsing: text)
        
        // Step 2: Convert to our thread-safe Native AST.
        var visitor = MarkdownKitVisitor()
        var rawNodes = visitor.defaultVisit(document)
        
        // Step 3: Run middleware plugins to modify the tree (e.g. inject MathNodes).
        for plugin in plugins {
            rawNodes = plugin.visit(rawNodes)
        }
        
        // Step 4: Return wrapped Document
        return DocumentNode(range: document.range, children: rawNodes)
    }
}
