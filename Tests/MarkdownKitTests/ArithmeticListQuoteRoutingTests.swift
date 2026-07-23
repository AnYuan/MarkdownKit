import XCTest
import Markdown
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct UnmodeledRoutingInlineNode: InlineNode {
    let id = UUID()
    let range: SourceRange? = nil
    let children: [MarkdownNode]
    let contentFingerprint: Int

    init(children: [MarkdownNode]) {
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "UnmodeledRoutingInlineNode",
            children: children
        )
    }
}

final class ArithmeticListQuoteRoutingTests: XCTestCase {
    private let widths: [CGFloat] = [96, 220, 640]

    private enum SolverMode: CaseIterable {
        case sync
        case async
        case cancellable

        var label: String {
            switch self {
            case .sync: return "sync"
            case .async: return "async"
            case .cancellable: return "cancellable"
            }
        }
    }

    private func paragraph(_ text: String = "body") -> ParagraphNode {
        ParagraphNode(range: nil, children: [TextNode(range: nil, text: text)])
    }

    private func header(_ text: String = "heading") -> HeaderNode {
        HeaderNode(range: nil, level: 2, children: [TextNode(range: nil, text: text)])
    }

    private func item(
        _ children: [MarkdownNode],
        checkbox: CheckboxState = .none
    ) -> ListItemNode {
        ListItemNode(range: nil, checkbox: checkbox, children: children)
    }

    private func list(
        _ children: [MarkdownNode],
        ordered: Bool = false
    ) -> ListNode {
        ListNode(range: nil, isOrdered: ordered, children: children)
    }

    private func quote(_ children: [MarkdownNode]) -> BlockQuoteNode {
        BlockQuoteNode(range: nil, children: children)
    }

    private func makeBuilder(theme: Theme = .default) -> AttributedStringBuilder {
        let appearance = MarkdownAppearance.light
        let resolvedTheme = theme.resolved(for: appearance)
        return AttributedStringBuilder(
            theme: resolvedTheme,
            highlighter: SplashHighlighter(theme: resolvedTheme),
            diagramRegistry: DiagramAdapterRegistry(),
            mathAdapter: DefaultMathRenderingAdapter(),
            imageLoadingPolicy: .default,
            appearance: appearance
        )
    }

    private func customTheme() -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: base.colors,
            codeBlock: base.codeBlock,
            blockQuote: Theme.BlockQuoteStyle(indent: 23, barCharacter: "▌ "),
            list: Theme.ListStyle(
                bulletCharacter: "◦ ",
                checkedCharacter: "✓ ",
                uncheckedCharacter: "□ ",
                nestedIndentDelta: 21
            ),
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }

    private func positionDependentPrefixTheme() -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: base.colors,
            codeBlock: base.codeBlock,
            blockQuote: Theme.BlockQuoteStyle(indent: 16, barCharacter: "┃\t"),
            list: Theme.ListStyle(
                bulletCharacter: "•\t",
                checkedCharacter: "☑\t",
                uncheckedCharacter: "☐\t",
                nestedIndentDelta: base.list.nestedIndentDelta
            ),
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }

    #if canImport(AppKit)
    private func allGlyphFallbackTheme(font: Font) -> Theme {
        let base = Theme.default
        let paragraph = TypographyToken(
            font: font,
            lineHeightMultiple: 1.2,
            paragraphSpacing: base.typography.paragraph.paragraphSpacing
        )
        return Theme(
            typography: Theme.Typography(
                header1: base.typography.header1,
                header2: base.typography.header2,
                header3: base.typography.header3,
                paragraph: paragraph,
                codeBlock: base.typography.codeBlock
            ),
            colors: base.colors,
            codeBlock: base.codeBlock,
            blockQuote: base.blockQuote,
            list: base.list,
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }
    #endif

    private func rootNode<T: MarkdownNode>(
        _ markdown: String,
        as type: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> T {
        let document = MarkdownKitEngine.makeParser().parse(markdown)
        XCTAssertEqual(document.children.count, 1, file: file, line: line)
        return try XCTUnwrap(document.children.first as? T, file: file, line: line)
    }

    private func assertBuilderBackedParity(
        _ node: MarkdownNode,
        theme: Theme = .default,
        widths: [CGFloat]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let attributedString = makeBuilder(theme: theme).buildStringSync(
            for: node,
            constrainedToWidth: 640
        )
        let arithmetic = ArithmeticTextCalculator()
        let profile = arithmetic.profile(for: attributedString)
        XCTAssertTrue(profile.supportsArithmeticLayout, file: file, line: line)

        let prepared = arithmetic.prepare(attributedString: attributedString)
        let textKit = TextKitCalculator()
        for width in widths ?? self.widths {
            let arithmeticSize = arithmetic.layout(
                prepared: prepared,
                constrainedToWidth: width
            )
            let oracleSize = textKit.calculateSize(
                for: attributedString,
                constrainedToWidth: width
            )
            XCTAssertEqual(
                arithmeticSize.width,
                oracleSize.width,
                accuracy: 1,
                "Width drift at \(width): arithmetic=\(arithmeticSize), TextKit=\(oracleSize)",
                file: file,
                line: line
            )
            XCTAssertEqual(
                arithmeticSize.height,
                oracleSize.height,
                accuracy: 0.001,
                "Height drift at \(width): arithmetic=\(arithmeticSize), TextKit=\(oracleSize)",
                file: file,
                line: line
            )
        }
    }

    private func makeSolver(
        theme: Theme = .default,
        preparedCache: PreparedContentCache
    ) -> LayoutSolver {
        LayoutSolver(
            theme: theme,
            cache: LayoutCache(),
            mathAdapter: RoutingMathAdapter(),
            imageLoadingPolicy: .disabled,
            preparedCache: preparedCache
        )
    }

    private func solve(
        _ node: MarkdownNode,
        width: CGFloat,
        mode: SolverMode,
        solver: LayoutSolver,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> LayoutResult {
        switch mode {
        case .sync:
            return solver.solveSync(node: node, constrainedToWidth: width)
        case .async:
            return await solver.solve(node: node, constrainedToWidth: width)
        case .cancellable:
            let result = await solver.solveCancellable(
                node: node,
                constrainedToWidth: width
            )
            return try XCTUnwrap(result, file: file, line: line)
        }
    }

    private func assertTextKitParity(
        _ result: LayoutResult,
        width: CGFloat,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let attributedString = try XCTUnwrap(
            result.attributedString,
            "\(context) must produce attributed text",
            file: file,
            line: line
        )
        let oracle = TextKitCalculator().calculateSize(
            for: attributedString,
            constrainedToWidth: width
        )
        XCTAssertEqual(
            result.size.width,
            oracle.width,
            accuracy: 1,
            "\(context) width drift: solver=\(result.size), TextKit=\(oracle)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            result.size.height,
            oracle.height,
            accuracy: 0.001,
            "\(context) height drift: solver=\(result.size), TextKit=\(oracle)",
            file: file,
            line: line
        )
    }

    private func assertArithmeticPreparedReuse(
        _ node: MarkdownNode,
        name: String,
        mode: SolverMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let context = "\(name) [\(mode.label)]"
        XCTAssertTrue(
            LayoutSolver.supportsArithmeticLayoutStructure(node),
            context,
            file: file,
            line: line
        )

        let preparedCache = PreparedContentCache()
        let solver = makeSolver(preparedCache: preparedCache)
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
        defer { ArithmeticTextCalculator.resetPreparedTextCacheForTesting() }

        let firstWidth: CGFloat = 180
        let first = try await solve(
            node,
            width: firstWidth,
            mode: mode,
            solver: solver,
            file: file,
            line: line
        )
        XCTAssertEqual(preparedCache.entryCountForTesting, 1, context, file: file, line: line)
        XCTAssertEqual(preparedCache.missCountForTesting, 1, context, file: file, line: line)
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 0,
            context,
            file: file,
            line: line
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 1,
            "\(context) prepared miss must create an arithmetic plan",
            file: file,
            line: line
        )
        try assertTextKitParity(
            first,
            width: firstWidth,
            context: "\(context) first width",
            file: file,
            line: line
        )

        preparedCache.resetDiagnosticsForTesting()
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
        let secondWidth: CGFloat = 520
        let second = try await solve(
            node,
            width: secondWidth,
            mode: mode,
            solver: solver,
            file: file,
            line: line
        )
        XCTAssertEqual(preparedCache.entryCountForTesting, 1, context, file: file, line: line)
        XCTAssertEqual(preparedCache.hitCountForTesting, 1, context, file: file, line: line)
        XCTAssertEqual(preparedCache.missCountForTesting, 0, context, file: file, line: line)
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 0,
            "\(context) prepared hit must bypass the global arithmetic cache",
            file: file,
            line: line
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 0,
            "\(context) prepared hit must not re-prepare",
            file: file,
            line: line
        )
        try assertTextKitParity(
            second,
            width: secondWidth,
            context: "\(context) second width",
            file: file,
            line: line
        )
    }

    private func assertTextKitPreparedReuse(
        _ node: MarkdownNode,
        name: String,
        mode: SolverMode,
        expectsPreparedCache: Bool,
        theme: Theme = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let context = "\(name) [\(mode.label)]"
        let preparedCache = PreparedContentCache()
        let solver = makeSolver(theme: theme, preparedCache: preparedCache)
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
        defer { ArithmeticTextCalculator.resetPreparedTextCacheForTesting() }

        let firstWidth: CGFloat = 180
        let first = try await solve(
            node,
            width: firstWidth,
            mode: mode,
            solver: solver,
            file: file,
            line: line
        )
        XCTAssertEqual(
            preparedCache.entryCountForTesting,
            expectsPreparedCache ? 1 : 0,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(preparedCache.missCountForTesting, 1, context, file: file, line: line)
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 0,
            context,
            file: file,
            line: line
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 0,
            "\(context) must stay on TextKit",
            file: file,
            line: line
        )
        try assertTextKitParity(
            first,
            width: firstWidth,
            context: "\(context) first width",
            file: file,
            line: line
        )

        preparedCache.resetDiagnosticsForTesting()
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
        let secondWidth: CGFloat = 520
        let second = try await solve(
            node,
            width: secondWidth,
            mode: mode,
            solver: solver,
            file: file,
            line: line
        )
        XCTAssertEqual(
            preparedCache.entryCountForTesting,
            expectsPreparedCache ? 1 : 0,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            preparedCache.hitCountForTesting,
            expectsPreparedCache ? 1 : 0,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            preparedCache.missCountForTesting,
            expectsPreparedCache ? 0 : 1,
            context,
            file: file,
            line: line
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
            equals: 0,
            context,
            file: file,
            line: line
        )
        TestHelper.assertDebugCounter(
            ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
            equals: 0,
            "\(context) width relayout must stay on TextKit",
            file: file,
            line: line
        )
        try assertTextKitParity(
            second,
            width: secondWidth,
            context: "\(context) second width",
            file: file,
            line: line
        )
    }

    func testArithmeticStructureWhitelistAcceptsModeledRoots() {
        let leafList = list([item([paragraph()])])
        let nestedUnordered = list([item([paragraph("nested leaf")])])
        let nestedOrdered = list(
            [item([paragraph("middle"), nestedUnordered])],
            ordered: true
        )
        let depthThree = list([item([paragraph("outer"), nestedOrdered])])

        let accepted: [(String, MarkdownNode)] = [
            ("paragraph", paragraph()),
            ("header", header()),
            ("single paragraph quote", quote([paragraph()])),
            ("multi paragraph quote", quote([paragraph("one"), paragraph("two")])),
            ("unordered leaf list", leafList),
            ("ordered leaf list", list([item([paragraph()])], ordered: true)),
            ("task list", list([item([paragraph()], checkbox: .checked)])),
            ("mixed depth-three list", depthThree)
        ]

        for (name, node) in accepted {
            XCTAssertTrue(LayoutSolver.supportsArithmeticLayoutStructure(node), name)
        }
    }

    func testArithmeticStructureWhitelistRejectsMalformedLists() {
        let paragraph = paragraph()
        let nested = list([item([self.paragraph("nested")])])
        let malformed: [(String, MarkdownNode)] = [
            ("empty list", list([])),
            ("non-item child", list([paragraph])),
            ("empty item", list([item([])])),
            ("item without leading paragraph", list([item([header()])])),
            ("loose item", list([item([paragraph, self.paragraph("second")])])),
            ("nested list before paragraph", list([item([nested, paragraph])])),
            ("trailing paragraph after nested list", list([item([paragraph, nested, self.paragraph("tail")])])),
            ("two nested lists", list([item([paragraph, nested, nested])])),
            ("non-list second child", list([item([paragraph, header()])])),
            ("empty nested list", list([item([paragraph, list([])])])),
            ("thematic child", list([item([paragraph, ThematicBreakNode(range: nil)])]))
        ]

        for (name, node) in malformed {
            XCTAssertFalse(LayoutSolver.supportsArithmeticLayoutStructure(node), name)
        }
    }

    func testArithmeticStructureWhitelistRejectsUnsupportedQuotes() {
        let paragraph = paragraph()
        let unsupported: [(String, MarkdownNode)] = [
            ("empty quote", quote([])),
            ("quote with list", quote([paragraph, list([item([self.paragraph()])])])),
            ("quote with header", quote([paragraph, header()])),
            ("nested quote", quote([paragraph, quote([self.paragraph("nested")])])),
            ("quote with thematic break", quote([paragraph, ThematicBreakNode(range: nil)]))
        ]

        for (name, node) in unsupported {
            XCTAssertFalse(LayoutSolver.supportsArithmeticLayoutStructure(node), name)
        }
    }

    func testBuilderBackedNestedUnorderedListMatchesTextKit() throws {
        let list = try rootNode(
            """
            - Outer alpha has enough content to wrap at the narrow width
                - Nested beta also wraps under its own prefix
                    - Deep gamma preserves the builder's flattened nested style
                - Nested delta
            - Tail epsilon restores the outer prefix geometry
            """,
            as: ListNode.self
        )

        assertBuilderBackedParity(list)
        assertBuilderBackedParity(list, theme: customTheme())
    }

    func testBuilderBackedOrderedListAcrossDigitBoundaryMatchesTextKit() throws {
        let list = try rootNode(
            (1...12).map { index in
                "\(index). Ordered item \(index) has wrapping content for prefix-width coverage"
            }.joined(separator: "\n"),
            as: ListNode.self
        )

        let attributedString = makeBuilder().buildStringSync(
            for: list,
            constrainedToWidth: 640
        )
        XCTAssertTrue(attributedString.string.contains("9. Ordered"))
        XCTAssertTrue(attributedString.string.contains("10. Ordered"))
        assertBuilderBackedParity(list)
    }

    func testBuilderBackedTaskListMatchesTextKitAndKeepsCheckboxTextual() throws {
        let list = try rootNode(
            """
            - [x] Completed task has enough text to wrap at narrow widths
            - [ ] Pending task also wraps beneath its checkbox prefix
            - [x] Tail task
            """,
            as: ListNode.self
        )
        let attributedString = makeBuilder().buildStringSync(
            for: list,
            constrainedToWidth: 640
        )

        XCTAssertNil(attributedString.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertNotNil(attributedString.attribute(.markdownCheckbox, at: 0, effectiveRange: nil))
        assertBuilderBackedParity(list)
        assertBuilderBackedParity(list, theme: customTheme())
    }

    func testBuilderBackedMultiParagraphBlockQuoteMatchesTextKit() throws {
        let quote = try rootNode(
            """
            > First quoted paragraph has enough prose to wrap at the narrow width.
            >
            > Second paragraph contains **bold**, *italic*, and `inline code`.
            >
            > Third paragraph preserves the terminal empty line box.
            """,
            as: BlockQuoteNode.self
        )

        assertBuilderBackedParity(quote, widths: [80, 190, 640])
        assertBuilderBackedParity(quote, theme: customTheme(), widths: [80, 190, 640])
    }

    func testBuilderBackedMixedNestedListMatchesTextKit() throws {
        let list = try rootNode(
            """
            1. Ordered outer item wraps across lines
                - Nested unordered item one wraps as well
                - Nested unordered item two
            2. Ordered tail
            """,
            as: ListNode.self
        )

        assertBuilderBackedParity(list)
    }

    func testSupportedListsAndQuotesUseArithmeticAcrossEverySolverMode() async throws {
        let supported: [(String, MarkdownNode)] = [
            (
                "mixed nested list",
                try rootNode(
                    """
                    1. Ordered outer content wraps at the narrow width
                        - Nested unordered content also wraps beneath its prefix
                            1. Third level item
                    2. Ordered tail
                    """,
                    as: ListNode.self
                )
            ),
            (
                "multi-paragraph quote",
                try rootNode(
                    """
                    > First paragraph has enough text to wrap at a narrow width.
                    >
                    > Second paragraph includes **bold**, *italic*, and `inline code`.
                    """,
                    as: BlockQuoteNode.self
                )
            ),
            (
                "task list",
                try rootNode(
                    """
                    - [x] Completed task wraps beneath its checkbox prefix at narrow widths
                    - [ ] Pending task follows the same arithmetic routing path
                    """,
                    as: ListNode.self
                )
            )
        ]

        for mode in SolverMode.allCases {
            for (name, node) in supported {
                try await assertArithmeticPreparedReuse(node, name: name, mode: mode)
            }
        }
    }

    func testUnsupportedStructuresAndScriptsStayOnCachedTextKitPlans() async throws {
        let listContainingQuote = try rootNode(
            """
            > Intro paragraph.
            >
            > - Nested quoted list item
            > - Nested quoted tail
            """,
            as: BlockQuoteNode.self
        )
        let thematicList = list([
            item([paragraph("before break"), ThematicBreakNode(range: nil)])
        ])
        let thematicQuote = quote([
            paragraph("before break"),
            ThematicBreakNode(range: nil)
        ])
        let codeList = list([
            item([
                paragraph("before code"),
                CodeBlockNode(range: nil, language: "swift", code: "let value = 1")
            ])
        ])
        let detailsQuote = quote([
            paragraph("before details"),
            DetailsNode(
                range: nil,
                isOpen: true,
                summary: nil,
                children: [paragraph("details body")]
            )
        ])
        let unmodeledInlineList = list([
            item([
                ParagraphNode(
                    range: nil,
                    children: [
                        UnmodeledRoutingInlineNode(
                            children: [TextNode(range: nil, text: "custom inline body")]
                        )
                    ]
                )
            ])
        ])
        let splitGraphemeParagraph = ParagraphNode(
            range: nil,
            children: [
                TextNode(range: nil, text: "A supported prefix before e"),
                EmphasisNode(
                    range: nil,
                    children: [TextNode(range: nil, text: "\u{301} tail")]
                )
            ]
        )
        let textKitNodes: [(String, MarkdownNode)] = [
            (
                "unsupported-script list",
                try rootNode("- مرحبا بالعالم\n- عنصر ثان", as: ListNode.self)
            ),
            (
                "unsupported-script quote",
                try rootNode("> مرحبا بالعالم\n>\n> فقرة ثانية", as: BlockQuoteNode.self)
            ),
            ("list-containing quote", listContainingQuote),
            ("thematic list descendant", thematicList),
            ("thematic quote descendant", thematicQuote),
            ("code block list descendant", codeList),
            ("details quote descendant", detailsQuote),
            ("unmodeled public inline descendant", unmodeledInlineList),
            (
                "list with late attributed-run grapheme split",
                list([item([splitGraphemeParagraph])])
            ),
            (
                "quote with late attributed-run grapheme split",
                quote([splitGraphemeParagraph])
            )
        ]

        for mode in SolverMode.allCases {
            for (name, node) in textKitNodes {
                try await assertTextKitPreparedReuse(
                    node,
                    name: name,
                    mode: mode,
                    expectsPreparedCache: true
                )
            }
        }

        let positionDependentPrefixes: [(String, MarkdownNode)] = [
            ("tabbed bullet prefix", list([item([paragraph("unordered body")])])),
            (
                "tabbed checked prefix",
                list([item([paragraph("checked body")], checkbox: .checked)])
            ),
            (
                "tabbed unchecked prefix",
                list([item([paragraph("unchecked body")], checkbox: .unchecked)])
            ),
            ("tabbed quote bar", quote([paragraph("quoted body")]))
        ]
        for mode in SolverMode.allCases {
            for (name, node) in positionDependentPrefixes {
                try await assertTextKitPreparedReuse(
                    node,
                    name: name,
                    mode: mode,
                    expectsPreparedCache: true,
                    theme: positionDependentPrefixTheme()
                )
            }
        }

        #if canImport(AppKit)
        guard let helvetica = Font(name: "Helvetica", size: 16),
              let emojiFont = Font(name: "AppleColorEmoji", size: 16) else {
            XCTFail("Expected AppKit fallback-regression fonts")
            return
        }
        let prime = NSAttributedString(
            string: "Prime AppKit fallback state",
            attributes: [.font: helvetica]
        )
        _ = TextKitCalculator().calculateSize(for: prime, constrainedToWidth: 180)

        let fallbackTheme = allGlyphFallbackTheme(font: emojiFont)
        let fallbackNodes: [(String, MarkdownNode)] = [
            ("all-glyph-fallback list", list([item([paragraph("Hello")])])),
            ("all-glyph-fallback quote", quote([paragraph("Hello")]))
        ]
        for mode in SolverMode.allCases {
            for (name, node) in fallbackNodes {
                try await assertTextKitPreparedReuse(
                    node,
                    name: name,
                    mode: mode,
                    expectsPreparedCache: true,
                    theme: fallbackTheme
                )
            }
        }

        let oversizedPointFont = Font.systemFont(ofSize: CGFloat(Int.max) / 500)
        XCTAssertFalse(
            ArithmeticTextMeasurer.supportsArithmeticPointSize(oversizedPointFont.pointSize)
        )
        let oversizedPointTheme = allGlyphFallbackTheme(font: oversizedPointFont)
        let oversizedPointNodes: [(String, MarkdownNode)] = [
            ("uncacheable font point-size list", list([item([paragraph("Hello")])])),
            ("uncacheable font point-size quote", quote([paragraph("Hello")]))
        ]
        for mode in SolverMode.allCases {
            for (name, node) in oversizedPointNodes {
                try await assertTextKitPreparedReuse(
                    node,
                    name: name,
                    mode: mode,
                    expectsPreparedCache: true,
                    theme: oversizedPointTheme
                )
            }
        }
        #endif
    }

    func testResourceDescendantsStayOnTextKitAndAreNotPreparedCached() async throws {
        let mathParagraph = ParagraphNode(
            range: nil,
            children: [
                TextNode(range: nil, text: "Inline math "),
                MathNode(range: nil, style: .inline, equation: "x^2")
            ]
        )
        let imageParagraph = ParagraphNode(
            range: nil,
            children: [
                TextNode(range: nil, text: "Inline image "),
                ImageNode(
                    range: nil,
                    source: "https://example.invalid/image.png",
                    altText: "fallback",
                    title: nil
                )
            ]
        )
        let resources: [(String, MarkdownNode)] = [
            ("list with inline math", list([item([mathParagraph])])),
            ("quote with inline image", quote([imageParagraph]))
        ]

        for mode in SolverMode.allCases {
            for (name, node) in resources {
                XCTAssertTrue(LayoutSolver.supportsArithmeticLayoutStructure(node), name)
                try await assertTextKitPreparedReuse(
                    node,
                    name: name,
                    mode: mode,
                    expectsPreparedCache: false
                )
            }
        }
    }

    func testUnsupportedScriptProfilesRemainIneligible() throws {
        let nodes: [MarkdownNode] = [
            try rootNode("- مرحبا بالعالم\n- عنصر ثان", as: ListNode.self),
            try rootNode("> مرحبا بالعالم\n>\n> فقرة ثانية", as: BlockQuoteNode.self)
        ]
        let arithmetic = ArithmeticTextCalculator()

        for node in nodes {
            let attributedString = makeBuilder().buildStringSync(
                for: node,
                constrainedToWidth: 320
            )
            XCTAssertFalse(arithmetic.profile(for: attributedString).supportsArithmeticLayout)
        }
    }

    func testNarrowFallbackOnlyTaskLineUsesTextKitAndReusesArithmeticPlan() async throws {
        #if canImport(AppKit)
        let helvetica = try XCTUnwrap(Font(name: "Helvetica", size: 16))
        _ = TextKitCalculator().calculateSize(
            for: NSAttributedString(
                string: "Prime AppKit fallback state",
                attributes: [.font: helvetica]
            ),
            constrainedToWidth: 180
        )
        let taskList = try rootNode("- [ ] Pending", as: ListNode.self)

        for mode in SolverMode.allCases {
            let context = "narrow task fallback [\(mode.label)]"
            let preparedCache = PreparedContentCache()
            let solver = makeSolver(preparedCache: preparedCache)
            ArithmeticTextCalculator.resetPreparedTextCacheForTesting()

            let narrowWidth: CGFloat = 10
            let narrowResult = try await solve(
                taskList,
                width: narrowWidth,
                mode: mode,
                solver: solver
            )
            XCTAssertEqual(preparedCache.entryCountForTesting, 1, context)
            XCTAssertEqual(preparedCache.missCountForTesting, 1, context)
            try assertTextKitParity(
                narrowResult,
                width: narrowWidth,
                context: context
            )

            let narrowString = try XCTUnwrap(narrowResult.attributedString)
            let arithmetic = ArithmeticTextCalculator()
            let narrowOutcome = arithmetic.layoutOutcome(
                prepared: ArithmeticTextMeasurer.prepare(attributedString: narrowString),
                constrainedToWidth: narrowWidth
            )
            let narrowOracle = TextKitCalculator().calculateSize(
                for: narrowString,
                constrainedToWidth: narrowWidth
            )
            XCTAssertTrue(narrowOutcome.requiresTextKitFallback, context)
            XCTAssertNotEqual(
                narrowOutcome.size.height,
                narrowOracle.height,
                "The regression fixture must distinguish arithmetic from TextKit",
                file: #filePath,
                line: #line
            )

            preparedCache.resetDiagnosticsForTesting()
            ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
            let normalWidth: CGFloat = 240
            let normalResult = try await solve(
                taskList,
                width: normalWidth,
                mode: mode,
                solver: solver
            )
            XCTAssertEqual(preparedCache.hitCountForTesting, 1, context)
            XCTAssertEqual(preparedCache.missCountForTesting, 0, context)
            TestHelper.assertDebugCounter(
                ArithmeticTextCalculator.preparedTextCacheHitsForTesting(),
                equals: 0,
                context
            )
            TestHelper.assertDebugCounter(
                ArithmeticTextCalculator.preparedTextCacheMissesForTesting(),
                equals: 0,
                context
            )

            let normalString = try XCTUnwrap(normalResult.attributedString)
            let normalOutcome = arithmetic.layoutOutcome(
                prepared: ArithmeticTextMeasurer.prepare(attributedString: normalString),
                constrainedToWidth: normalWidth
            )
            XCTAssertFalse(normalOutcome.requiresTextKitFallback, context)
            XCTAssertEqual(normalResult.size, normalOutcome.size, context)
            try assertTextKitParity(
                normalResult,
                width: normalWidth,
                context: "\(context) normal width"
            )
        }
        ArithmeticTextCalculator.resetPreparedTextCacheForTesting()
        #endif
    }
}

private struct RoutingMathAdapter: MathRenderingAdapter {
    func render(
        from node: MathNode,
        theme: Theme,
        contextFont: Font?
    ) async -> NSAttributedString {
        NSAttributedString(string: "<math:\(node.equation)>")
    }

    func renderSync(
        from node: MathNode,
        theme: Theme,
        contextFont: Font?
    ) -> NSAttributedString {
        NSAttributedString(string: "<math:\(node.equation)>")
    }
}
