import Foundation
import Markdown
import os

/// The main entry point for parsing raw Markdown strings into our high-performance
/// AST, executing any injected middleware plugins along the way.
///
/// - Important: `MarkdownParser` is **not** `Sendable`. Its `plugins` array may contain
///   host-supplied `ASTPlugin` values that are not themselves `Sendable`, so a parser
///   instance (and any pipeline of plugins configured on it) must stay confined to a
///   single task or actor. Do not share or copy a configured parser across concurrent
///   tasks; construct each parser with task-confined plugin instances instead.
public struct MarkdownParser {

    private static let logger = Logger(subsystem: "com.markdownkit", category: "Parser")

    /// Per-parser resource policy bounding worst-case input size and native-AST recursion.
    ///
    /// These limits protect the mapping stage from pathological inputs (extremely large
    /// documents or deeply nested markup) without relying on shared, mutable, process-global
    /// state. Each `MarkdownParser` instance carries its own `ResourceLimits`, so different
    /// call sites (e.g. a permissive batch importer vs. a strict live-typing editor) can
    /// configure independent policies safely.
    public struct ResourceLimits: Sendable, Equatable {
        /// The maximum allowed input size, measured in UTF-8 bytes.
        ///
        /// This is an inclusive boundary: an input whose UTF-8 byte count is exactly equal to
        /// `maximumInputBytes` is accepted; only inputs whose UTF-8 byte count is strictly
        /// greater than `maximumInputBytes` are rejected.
        public let maximumInputBytes: Int

        /// The maximum container-nesting depth retained while mapping the
        /// `swift-markdown` syntax tree into MarkdownKit's native `MarkdownNode` model.
        ///
        /// This bounds only the native-AST mapping recursion performed by
        /// `MarkdownKitVisitor` — it is **not** a limit enforced by the `swift-markdown`
        /// front-end parser, and it is **not** a layout/rendering depth limit. The root
        /// `Document` is not counted. When the limit is reached, the boundary container
        /// remains in the native tree while its descendants are omitted. Leaf markup does
        /// not recurse and therefore does not consume another nesting level.
        public let maximumNestingDepth: Int

        /// Creates a resource policy, normalizing hostile or invalid configuration so it can
        /// never crash the parser.
        ///
        /// - Parameters:
        ///   - maximumInputBytes: Desired byte ceiling. Negative values are clamped to `0`.
        ///   - maximumNestingDepth: Desired recursion budget. Values below `1` are clamped to `1`.
        public init(maximumInputBytes: Int = 1_048_576, maximumNestingDepth: Int = 50) {
            self.maximumInputBytes = max(0, maximumInputBytes)
            self.maximumNestingDepth = max(1, maximumNestingDepth)
        }

        /// The default resource policy: 1 MiB maximum input and 50 retained
        /// container-nesting levels beneath the root document.
        public static let `default` = ResourceLimits()
    }

    /// A machine-readable description of a resource-policy condition encountered while parsing.
    public enum Diagnostic: Sendable, Equatable {
        /// The input's UTF-8 byte count exceeded `ResourceLimits.maximumInputBytes`.
        case inputTooLarge(actualBytes: Int, maximumBytes: Int)
        /// Native-AST mapping recursion reached `ResourceLimits.maximumNestingDepth` and
        /// omitted some descendant content to avoid unbounded recursion.
        case maximumNestingDepthExceeded(maximumDepth: Int)
    }

    /// The typed result of attempting to parse a Markdown string.
    public enum ParseOutcome: Sendable {
        /// Parsing (and plugin execution) completed, possibly with non-fatal diagnostics
        /// such as a depth-truncated subtree.
        case parsed(document: DocumentNode, diagnostics: [Diagnostic])
        /// The input was rejected before any `swift-markdown` parsing or plugin execution.
        case rejected(diagnostic: Diagnostic)

        /// The resulting document, or `nil` if the input was rejected.
        public var document: DocumentNode? {
            switch self {
            case .parsed(let document, _):
                return document
            case .rejected:
                return nil
            }
        }

        /// All diagnostics produced while handling this input. Contains exactly one
        /// element for a `.rejected` outcome.
        public var diagnostics: [Diagnostic] {
            switch self {
            case .parsed(_, let diagnostics):
                return diagnostics
            case .rejected(let diagnostic):
                return [diagnostic]
            }
        }

        /// `true` if the input was rejected outright (i.e. never reached `swift-markdown`
        /// or the plugin pipeline).
        public var isRejected: Bool {
            switch self {
            case .parsed:
                return false
            case .rejected:
                return true
            }
        }
    }

    /// The plugins that will be executed sequentially on the tree after the initial parse.
    public var plugins: [ASTPlugin]

    /// The resource policy applied by this parser instance.
    public let limits: ResourceLimits

    public init(plugins: [ASTPlugin] = [], limits: ResourceLimits = .default) {
        self.plugins = plugins
        self.limits = limits
    }

    /// Parses a raw Markdown string into a typed `ParseOutcome`.
    ///
    /// - Parameter text: The raw markdown content.
    /// - Returns: `.rejected` if `text`'s UTF-8 byte count exceeds `limits.maximumInputBytes`
    ///   (checked before any `swift-markdown` parsing or plugin execution runs), otherwise
    ///   `.parsed` with the resulting document and any non-fatal diagnostics (for example, a
    ///   `.maximumNestingDepthExceeded` diagnostic if the document was truncated because it
    ///   exceeded `limits.maximumNestingDepth`).
    ///
    /// This method never logs; callers that want diagnostics surfaced via the parser's
    /// logger should use `parse(_:)` or inspect `diagnostics` themselves.
    public func parseOutcome(_ text: String) -> ParseOutcome {
        let actualBytes = text.utf8.count
        guard actualBytes <= limits.maximumInputBytes else {
            return .rejected(
                diagnostic: .inputTooLarge(actualBytes: actualBytes, maximumBytes: limits.maximumInputBytes)
            )
        }

        // Step 1: Parse using Apple's highly-optimized C-backend.
        let document = Document(parsing: text)

        // Step 2: Convert to our thread-safe Native AST.
        var visitor = MarkdownKitVisitor(maxDepth: limits.maximumNestingDepth)
        var rawNodes = visitor.defaultVisit(document)

        // Step 3: Run middleware plugins to modify the tree (e.g. inject MathNodes).
        //
        // Built-in plugins that adopt `BuiltInSourcePreflightPlugin` (Details,
        // Diagram, Math) may be skipped entirely while no earlier plugin in this
        // parse has actually executed, if `BuiltInPluginSourceHints` — computed
        // lazily at most once per parse, from the original source text — prove
        // the source cannot contain syntax that plugin cares about. Skipping
        // preserves eligibility for later plugins; once *any* plugin executes
        // (built-in or custom), every remaining plugin runs normally, because
        // its output could introduce syntax absent from the original source.
        var anyPluginExecuted = false
        var cachedSourceHints: BuiltInPluginSourceHints?
        for plugin in plugins {
            if !anyPluginExecuted, let preflightType = type(of: plugin) as? any BuiltInSourcePreflightPlugin.Type {
                let hints = cachedSourceHints ?? BuiltInPluginSourceHints(source: text)
                cachedSourceHints = hints
                if !preflightType.mightApply(given: hints) {
                    continue
                }
            }
            rawNodes = plugin.visit(rawNodes)
            anyPluginExecuted = true
        }

        // Step 4: Return wrapped Document, plus a diagnostic if mapping was truncated.
        var diagnostics: [Diagnostic] = []
        if visitor.didTruncateAtMaximumDepth {
            diagnostics.append(.maximumNestingDepthExceeded(maximumDepth: limits.maximumNestingDepth))
        }
        let documentNode = DocumentNode(range: document.range, children: rawNodes)
        return .parsed(document: documentNode, diagnostics: diagnostics)
    }

    /// Parses a raw Markdown string into the `MarkdownKit` AST representation.
    ///
    /// - Parameter text: The raw markdown content.
    /// - Returns: The root `DocumentNode` containing the structured tree, or the historical
    ///   empty `DocumentNode(range: nil, children: [])` if `text` was rejected for exceeding
    ///   `limits.maximumInputBytes`.
    ///
    /// This is a lossy compatibility convenience over `parseOutcome(_:)`: it logs each
    /// diagnostic via the parser's logger and collapses rejection into an empty document,
    /// discarding the distinction between "rejected" and "parsed with no content". Callers
    /// that need to distinguish those cases, or need programmatic access to diagnostics,
    /// must use `parseOutcome(_:)` instead.
    public func parse(_ text: String) -> DocumentNode {
        let outcome = parseOutcome(text)
        for diagnostic in outcome.diagnostics {
            switch diagnostic {
            case .inputTooLarge(let actualBytes, let maximumBytes):
                Self.logger.warning("Input exceeds max size (\(actualBytes) bytes > \(maximumBytes)). Returning empty document.")
            case .maximumNestingDepthExceeded(let maximumDepth):
                Self.logger.warning("Native AST mapping reached maximum nesting depth (\(maximumDepth)). Returning partial document.")
            }
        }
        return outcome.document ?? DocumentNode(range: nil, children: [])
    }
}
