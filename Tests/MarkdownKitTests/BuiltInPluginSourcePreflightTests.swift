import XCTest
@testable import MarkdownKit

/// Covers the `BuiltInPluginSourcePreflight` skip contract: `BuiltInPluginSourceHints`
/// predicates, and `MarkdownParser`'s "skip while nothing has executed yet, otherwise
/// always run" rule for plugins adopting the internal `BuiltInSourcePreflightPlugin`
/// protocol.
final class BuiltInPluginSourcePreflightTests: XCTestCase {

    // MARK: - Test doubles

    private final class VisitCounter {
        var count = 0
    }

    /// A synthetic preflight-capable plugin. It reuses `mayContainMathSyntax` as its
    /// "might apply" condition purely so this test can drive it with ordinary source
    /// text, without needing any production built-in's exact syntax rules. Its
    /// production counterparts are `DetailsExtractionPlugin`, `DiagramExtractionPlugin`,
    /// and `MathExtractionPlugin` — this type never ships outside test targets.
    private struct SyntheticPreflightPlugin: ASTPlugin, BuiltInSourcePreflightPlugin {
        let counter: VisitCounter

        func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
            counter.count += 1
            return nodes
        }

        static func mightApply(given hints: BuiltInPluginSourceHints) -> Bool {
            hints.mayContainMathSyntax
        }
    }

    private struct CountingCustomPlugin: ASTPlugin {
        let counter: VisitCounter

        func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
            counter.count += 1
            return nodes
        }
    }

    // MARK: - Parser-level skip contract

    func testPreflightCapablePluginIsNotVisitedOnIrrelevantSource() {
        let counter = VisitCounter()
        _ = TestHelper.parse(
            "Just a plain paragraph with no relevant markup.",
            plugins: [SyntheticPreflightPlugin(counter: counter)]
        )
        XCTAssertEqual(counter.count, 0, "A preflight-capable plugin must not be visited when hints are negative")
    }

    func testPreflightCapablePluginsRunForLiteralAndEntityDecodedRelevantSource() {
        let counter = VisitCounter()
        _ = TestHelper.parse(
            "Inline math present: $x^2$",
            plugins: [SyntheticPreflightPlugin(counter: counter)]
        )
        XCTAssertEqual(counter.count, 1, "A preflight-capable plugin must be visited when hints are positive")

        let details = TestHelper.parse(
            """
            &lt;details&gt;

            &lt;summary&gt;Info&lt;/summary&gt;

            Body

            &lt;/details&gt;
            """,
            plugins: [DetailsExtractionPlugin()]
        )
        XCTAssertTrue(containsNode(DetailsNode.self, in: details))

        let math = TestHelper.parse(
            "Encoded math: &#36;x^2&#36;",
            plugins: [MathExtractionPlugin()]
        )
        XCTAssertTrue(containsNode(MathNode.self, in: math))

        let diagram = TestHelper.parse(
            """
            ```mer&#109;aid
            graph TD
            A-->B
            ```
            """,
            plugins: [DiagramExtractionPlugin()]
        )
        XCTAssertTrue(containsNode(DiagramNode.self, in: diagram))

        let mixed = TestHelper.parse(
            """
            $x$

            ```mermaid
            graph TD
            A-->B
            ```

            &lt;details&gt;

            &lt;summary&gt;Info&lt;/summary&gt;

            Body

            &lt;/details&gt;
            """,
            plugins: MarkdownKitEngine.defaultPlugins()
        )
        XCTAssertTrue(
            containsNode(DetailsNode.self, in: mixed),
            "Finding literal math and diagram syntax must not stop the source scan before a later entity reference"
        )
    }

    func testCustomPluginBeforeBuiltInForcesLaterBuiltInToExecute() {
        let customCounter = VisitCounter()
        let builtInCounter = VisitCounter()

        _ = TestHelper.parse(
            "Just a plain paragraph with no relevant markup.",
            plugins: [
                CountingCustomPlugin(counter: customCounter),
                SyntheticPreflightPlugin(counter: builtInCounter)
            ]
        )

        XCTAssertEqual(customCounter.count, 1, "Custom plugin always executes")
        XCTAssertEqual(
            builtInCounter.count, 1,
            "A custom plugin executing before a preflight-capable plugin must force it to run, despite negative hints"
        )
    }

    func testCustomPluginAfterSkippedBuiltInDoesNotRetroactivelyForceEarlierSkip() {
        let builtInCounter = VisitCounter()
        let customCounter = VisitCounter()

        _ = TestHelper.parse(
            "Just a plain paragraph with no relevant markup.",
            plugins: [
                SyntheticPreflightPlugin(counter: builtInCounter),
                CountingCustomPlugin(counter: customCounter)
            ]
        )

        XCTAssertEqual(
            builtInCounter.count, 0,
            "An earlier preflight-capable plugin must remain skipped even though a later custom plugin runs"
        )
        XCTAssertEqual(customCounter.count, 1, "The later custom plugin always executes")
    }

    func testCustomPluginCanInjectMathSyntaxAbsentFromRawSourceAndMathExtractionPluginStillTransformsIt() {
        struct DollarInjectorPlugin: ASTPlugin {
            func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
                nodes.map { node in
                    guard node is ParagraphNode else { return node }
                    return ParagraphNode(range: nil, children: [TextNode(range: nil, text: "$E=mc^2$")])
                }
            }
        }

        let rawSource = "Just a plain paragraph with no dollar signs at all."
        XCTAssertFalse(rawSource.contains("$"), "Precondition: raw source must not contain any math markers")

        let doc = TestHelper.parse(rawSource, plugins: [DollarInjectorPlugin(), MathExtractionPlugin()])

        func findMathNode(in node: MarkdownNode) -> MathNode? {
            if let math = node as? MathNode { return math }
            for child in node.children {
                if let found = findMathNode(in: child) { return found }
            }
            return nil
        }

        let math = doc.children.compactMap(findMathNode).first
        XCTAssertNotNil(math, "MathExtractionPlugin must transform math syntax injected by an earlier custom plugin")
        XCTAssertEqual(math?.equation, "E=mc^2")
        XCTAssertEqual(math?.style, .inline)
    }

    func testRejectedOversizedInputNeverComputesHints() {
        // Regression guard: rejected input must never reach the plugin loop (and
        // therefore never compute BuiltInPluginSourceHints or invoke any plugin).
        let counter = VisitCounter()
        let limits = MarkdownParser.ResourceLimits(maximumInputBytes: 4, maximumNestingDepth: 50)
        let parser = MarkdownParser(plugins: [SyntheticPreflightPlugin(counter: counter)], limits: limits)
        let outcome = parser.parseOutcome("$x^2$ way over the byte budget")
        XCTAssertTrue(outcome.isRejected)
        XCTAssertEqual(counter.count, 0, "Rejected input must never invoke any plugin")
    }

    // MARK: - BuiltInPluginSourceHints: details

    func testDetailsHintPositiveForOpenCloseCaseAndMalformedMarkers() {
        let positives = [
            "<details><summary>Info</summary>Body</details>",
            "<DETAILS><SUMMARY>Info</SUMMARY>Body</DETAILS>",
            "<Details Open>\n<Summary>Info</Summary>\nBody\n</Details>",
            "<details", // malformed: opener with no closing '>' or matching close tag
            "</summary>", // malformed: a stray close marker with nothing else
            "<details>\n<summary>Outer</summary>\n<details>\n<summary>Inner</summary>\nNested\n</details>\n</details>"
        ]

        for source in positives {
            let hints = BuiltInPluginSourceHints(source: source)
            XCTAssertTrue(hints.mayContainDetailsMarkup, "Expected a details hint for: \(source)")
        }
    }

    func testDetailsHintNegativeForUnrelatedPlainSource() {
        let hints = BuiltInPluginSourceHints(source: "Just a **bold** paragraph with a [link](https://example.com).")
        XCTAssertFalse(hints.mayContainDetailsMarkup)
        XCTAssertFalse(hints.mayContainDiagramFence)
        XCTAssertFalse(hints.mayContainMathSyntax)
    }

    // MARK: - BuiltInPluginSourceHints: diagram

    func testDiagramHintPositiveForEveryDiagramLanguageAcrossFenceVariants() {
        for language in DiagramLanguage.allCases {
            let raw = language.rawValue

            let variants = [
                "```\(raw)\ncontent\n```",
                "```  \(raw.uppercased())  \ncontent\n```",
                "~~~\(raw)\ncontent\n~~~",
                "````\(raw)\ncontent\n````",
                "> ````  \(raw.uppercased()) theme=dark\n> content\n> ````",
                "> ```\(raw)\n> content\n> ```",
                "- item\n  ```\(raw)\n  content\n  ```"
            ]

            for source in variants {
                let hints = BuiltInPluginSourceHints(source: source)
                XCTAssertTrue(
                    hints.mayContainDiagramFence,
                    "Expected a diagram hint for language '\(raw)' with source:\n\(source)"
                )
            }
        }
    }

    func testDiagramHintNegativeForUnsupportedLanguageAndBareProse() {
        let unsupportedFence = BuiltInPluginSourceHints(source: "```swift\nprint(\"hi\")\n```")
        XCTAssertFalse(unsupportedFence.mayContainDiagramFence)

        let bareProse = BuiltInPluginSourceHints(source: "This uses an STL container internally.")
        XCTAssertFalse(bareProse.mayContainDiagramFence, "Bare prose mentioning a language name must not alone trigger a diagram hint")
    }

    // MARK: - BuiltInPluginSourceHints: math

    func testMathHintPositiveForDollarSignsIncludingEscapedAndMalformedForms() {
        let positives = [
            "Inline math $x^2$",
            "Block math $$x^2$$",
            #"Escaped dollar \$x^2\$ still contains the character"#,
            "``` literal ``` then $x^2$",
            "$unterminated",
            "$$",
            "price is $5"
        ]

        for source in positives {
            let hints = BuiltInPluginSourceHints(source: source)
            XCTAssertTrue(hints.mayContainMathSyntax, "Expected a math hint for: \(source)")
        }
    }

    func testMathHintPositiveForMathFenceLanguagesAcrossCaseAndWhitespace() {
        let languages = ["math", "latex", "tex"]
        for language in languages {
            let variants = [
                "```\(language)\nx^2\n```",
                "```  \(language.uppercased())  \nx^2\n```",
                "> ````  \(language.uppercased()) title=equation\n> x^2\n> ````",
                "~~~\(language)\nx^2\n~~~"
            ]
            for source in variants {
                let hints = BuiltInPluginSourceHints(source: source)
                XCTAssertTrue(hints.mayContainMathSyntax, "Expected a math hint for fence language '\(language)' with source:\n\(source)")
            }
        }
    }

    func testMathHintNegativeForBareProseWithoutDollarOrFence() {
        let hints = BuiltInPluginSourceHints(source: "This is just some latex and text prose without any formula.")
        XCTAssertFalse(hints.mayContainMathSyntax, "Bare prose mentioning 'latex'/'text' without '$' or a fence must not trigger a math hint")
    }

    private func containsNode<T: MarkdownNode>(_ type: T.Type, in node: MarkdownNode) -> Bool {
        node is T || node.children.contains { containsNode(type, in: $0) }
    }
}
