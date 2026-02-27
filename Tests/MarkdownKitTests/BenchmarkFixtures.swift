import Foundation

/// Static markdown test documents of varying sizes and complexity profiles.
enum BenchmarkFixtures {

    // MARK: - Size tiers

    /// ~10 lines. Header, paragraph, bold/italic, link, blockquote, hr.
    static let small = """
    # Welcome to MarkdownKit

    This is a **bold** statement with some *italic* text.

    Here is a [link](https://example.com) and some `inline code`.

    > A simple blockquote.

    ---

    Final paragraph with **bold** and *emphasis*.
    """

    /// ~100 lines. Mixed content: headers, lists, code, table, image, blockquote.
    static let medium: String = {
        var lines: [String] = []
        lines.append("# MarkdownKit Feature Overview")
        lines.append("")
        lines.append("MarkdownKit is a high-performance rendering engine.")
        lines.append("")

        for idx in 1...5 {
            lines.append("## Section \(idx)")
            lines.append("")
            lines.append("Content for section \(idx). Includes **bold**, *italic*, and ~~strikethrough~~. Also `inline code` and a [link](https://example.com/\(idx)).")
            lines.append("")
        }

        lines.append("### Ordered Steps")
        lines.append("")
        for idx in 1...8 {
            lines.append("\(idx). Step number \(idx) in the process")
        }
        lines.append("")

        lines.append("### Features")
        lines.append("")
        lines.append("- Parsing")
        lines.append("  - CommonMark compliant")
        lines.append("  - GFM extensions")
        lines.append("- Layout")
        lines.append("  - TextKit 2 measurement")
        lines.append("  - Background thread safe")
        lines.append("- Rendering")
        lines.append("  - NSCollectionView")
        lines.append("  - UICollectionView")
        lines.append("")

        lines.append("```swift")
        lines.append("let parser = MarkdownParser()")
        lines.append("let doc = parser.parse(text)")
        lines.append("let solver = LayoutSolver()")
        lines.append("let layout = await solver.solve(node: doc, constrainedToWidth: 400)")
        lines.append("```")
        lines.append("")

        lines.append("| Feature | Status | Priority |")
        lines.append("|:--------|:------:|--------:|")
        lines.append("| Parsing | Done | High |")
        lines.append("| Layout | Done | High |")
        lines.append("| Math | WIP | Medium |")
        lines.append("| Diagrams | Planned | Low |")
        lines.append("")

        lines.append("![Architecture](https://example.com/arch.png)")
        lines.append("")

        lines.append("> This is a blockquote spanning")
        lines.append("> multiple lines of text.")
        lines.append("")

        lines.append("---")
        lines.append("")
        lines.append("End of the medium fixture document.")

        return lines.joined(separator: "\n")
    }()

    /// ~1000 lines. Stress test with deep nesting, many code blocks, large tables.
    static let large: String = {
        var lines: [String] = []
        lines.append("# MarkdownKit Comprehensive Stress Test")
        lines.append("")

        for section in 1...20 {
            lines.append("## Section \(section): Feature Group \(section)")
            lines.append("")
            for para in 1...3 {
                lines.append("Paragraph \(para) of section \(section). Contains **bold text**, *italic text*, `inline code`, and a [link](https://example.com/\(section)/\(para)). Verbose content to stress-test the attributed string builder and TextKit measurement engine with realistic content lengths.")
                lines.append("")
            }

            if section % 3 == 0 {
                lines.append("```swift")
                for line in 1...10 {
                    lines.append("    let value\(line) = computeResult(\(line), factor: \(section))")
                }
                lines.append("```")
                lines.append("")
            }

            if section % 4 == 0 {
                for item in 1...5 {
                    lines.append("- Item \(item)")
                    lines.append("  - Sub-item \(item).1")
                    lines.append("  - Sub-item \(item).2")
                    lines.append("    - Deep-item \(item).2.1")
                }
                lines.append("")
            }

            if section % 5 == 0 {
                lines.append("| Col1 | Col2 | Col3 | Col4 | Col5 |")
                lines.append("|:-----|:----:|-----:|------|------|")
                for row in 1...10 {
                    lines.append("| R\(row)C1 | R\(row)C2 | R\(row)C3 | R\(row)C4 | R\(row)C5 |")
                }
                lines.append("")
            }
        }

        lines.append("---")
        lines.append("")
        lines.append("End of stress test document.")
        return lines.joined(separator: "\n")
    }()

    // MARK: - Content-specific fixtures

    /// 11 code blocks with different languages.
    static let codeHeavy: String = {
        let languages = ["swift", "python", "javascript", "rust", "go",
                         "java", "ruby", "kotlin", "typescript", "c", "cpp"]
        var lines: [String] = []
        lines.append("# Code-Heavy Document")
        lines.append("")

        for (idx, lang) in languages.enumerated() {
            lines.append("## Example \(idx + 1): \(lang)")
            lines.append("")
            lines.append("```\(lang)")
            for line in 1...8 {
                lines.append("// Line \(line) of \(lang) code: let x\(line) = process(\(line))")
            }
            lines.append("```")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }()

    /// 4 large tables (6-9 columns, 25 rows each).
    static let tableHeavy: String = {
        var lines: [String] = []
        lines.append("# Table-Heavy Document")
        lines.append("")

        for tableIdx in 1...4 {
            lines.append("## Table \(tableIdx)")
            lines.append("")
            let cols = 5 + tableIdx
            let header = (1...cols).map { "Col\($0)" }.joined(separator: " | ")
            lines.append("| \(header) |")
            let sep = (1...cols).map { _ in "------" }.joined(separator: " | ")
            lines.append("| \(sep) |")
            for row in 1...25 {
                let cells = (1...cols).map { "T\(tableIdx)R\(row)C\($0)" }.joined(separator: " | ")
                lines.append("| \(cells) |")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }()

    /// 20 math expressions (10 inline + 10 block).
    static let mathHeavy: String = {
        var lines: [String] = []
        lines.append("# Math-Heavy Document")
        lines.append("")

        let inlineEquations = [
            "E = mc^2", "a^2 + b^2 = c^2", "\\frac{1}{2}",
            "\\sqrt{x^2 + y^2}", "\\int_0^\\infty e^{-x} dx",
            "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}", "\\lim_{x \\to 0} \\frac{\\sin x}{x}",
            "\\binom{n}{k}", "\\nabla \\cdot \\vec{F}", "\\alpha + \\beta = \\gamma",
        ]
        let blockEquations = [
            "\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}",
            "\\frac{\\partial^2 u}{\\partial t^2} = c^2 \\nabla^2 u",
            "\\mathbf{F} = m\\mathbf{a}",
            "\\oint_C \\mathbf{B} \\cdot d\\mathbf{l} = \\mu_0 I",
            "\\hat{H}|\\psi\\rangle = E|\\psi\\rangle",
            "e^{i\\pi} + 1 = 0",
            "\\prod_{p \\text{ prime}} \\frac{1}{1-p^{-s}} = \\sum_{n=1}^{\\infty} \\frac{1}{n^s}",
            "\\det(A - \\lambda I) = 0",
            "\\mathcal{L}\\{f(t)\\} = \\int_0^\\infty e^{-st} f(t) dt",
            "\\frac{d}{dx} \\left[ \\int_a^x f(t) dt \\right] = f(x)",
        ]

        for (idx, equation) in inlineEquations.enumerated() {
            lines.append("Inline equation \(idx + 1): $\(equation)$ appears here in text.")
            lines.append("")
        }

        for (idx, equation) in blockEquations.enumerated() {
            lines.append("Block equation \(idx + 1):")
            lines.append("")
            lines.append("$$\(equation)$$")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }()

    /// 12 collapsible details blocks with mixed summaries/body content.
    static let detailsHeavy: String = {
        var lines: [String] = []
        lines.append("# Details-Heavy Document")
        lines.append("")

        for idx in 1...12 {
            let openFlag = idx % 2 == 0 ? " open" : ""
            lines.append("<details\(openFlag)>")
            lines.append("<summary>Section \(idx) Summary with **bold** text</summary>")
            lines.append("")
            lines.append("Paragraph \(idx) body content with *italic* text and a [link](https://example.com/details/\(idx)).")
            lines.append("")
            lines.append("- [ ] Todo item \(idx).1")
            lines.append("- [x] Todo item \(idx).2")
            lines.append("")
            lines.append("</details>")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }()

    /// 12 diagram fences across all supported diagram languages.
    static let diagramHeavy: String = {
        let languages = ["mermaid", "geojson", "topojson", "stl"]
        var lines: [String] = []
        lines.append("# Diagram-Heavy Document")
        lines.append("")

        for idx in 1...12 {
            let language = languages[(idx - 1) % languages.count]
            lines.append("## Diagram Block \(idx)")
            lines.append("")
            lines.append("```\(language)")
            switch language {
            case "mermaid":
                lines.append("graph TD")
                lines.append("  A\(idx) --> B\(idx)")
            case "geojson":
                lines.append("{ \"type\": \"Point\", \"coordinates\": [\(idx), \(idx + 1)] }")
            case "topojson":
                lines.append("{ \"type\": \"Topology\", \"objects\": { \"shape\": { \"type\": \"GeometryCollection\", \"geometries\": [] } } }")
            default:
                lines.append("solid shape\(idx)")
                lines.append("facet normal 0 0 0")
                lines.append("  outer loop")
                lines.append("    vertex 0 0 0")
                lines.append("    vertex 1 0 0")
                lines.append("    vertex 0 1 0")
                lines.append("  endloop")
                lines.append("endfacet")
                lines.append("endsolid")
            }
            lines.append("```")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }()

    /// 120-item checklist style list with checked/unchecked states.
    static let taskListHeavy: String = {
        var lines: [String] = []
        lines.append("# TaskList-Heavy Document")
        lines.append("")
        for idx in 1...120 {
            let marker = idx.isMultiple(of: 3) ? "[x]" : "[ ]"
            lines.append("- \(marker) Task item \(idx) with `inline code` and **bold** title")
        }
        return lines.joined(separator: "\n")
    }()

    /// All fixtures for iteration.
    static let allFixtures: [(name: String, content: String)] = [
        ("small", small),
        ("medium", medium),
        ("large", large),
        ("code-heavy", codeHeavy),
        ("table-heavy", tableHeavy),
        ("math-heavy", mathHeavy),
        ("details-heavy", detailsHeavy),
        ("diagram-heavy", diagramHeavy),
        ("tasklist-heavy", taskListHeavy),
    ]

    // MARK: - Per-node-type isolated fixtures

    /// 20 headers (H1-H3) with inline formatting, no other block types.
    static let headersOnly: String = {
        (1...20).map { idx in
            let level = ((idx - 1) % 3) + 1
            return "\(String(repeating: "#", count: level)) Header \(idx) with **bold** and *italic*"
        }.joined(separator: "\n\n")
    }()

    /// 20 paragraphs with full inline formatting variety.
    static let paragraphsOnly: String = {
        (1...20).map { idx in
            "Paragraph \(idx) with **bold text**, *italic text*, `inline code`, ~~strikethrough~~, and a [link](https://example.com/\(idx)). Additional text to make this paragraph substantive enough for realistic measurement."
        }.joined(separator: "\n\n")
    }()

    /// 5 fenced code blocks in different languages, 15 lines each.
    static let codeBlocksOnly: String = {
        let languages = ["swift", "python", "javascript", "rust", "go"]
        return languages.enumerated().map { (idx, lang) in
            "```\(lang)\n" + (1...15).map { "let x\($0) = compute(\($0), factor: \(idx))" }.joined(separator: "\n") + "\n```"
        }.joined(separator: "\n\n")
    }()

    /// 5 groups of 8-item unordered lists.
    static let unorderedListsOnly: String = {
        (1...5).map { section in
            (1...8).map { item in
                "- List \(section) item \(item) with **bold** content"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }()

    /// 5 groups of 8-item ordered lists.
    static let orderedListsOnly: String = {
        (1...5).map { section in
            (1...8).enumerated().map { (idx, _) in
                "\(idx + 1). Ordered list \(section) item \(idx + 1) with *italic* content"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }()

    /// 15 blockquotes with inline formatting.
    static let blockQuotesOnly: String = {
        (1...15).map { idx in
            "> Blockquote \(idx) with **bold** and *italic* formatting and a [link](https://example.com)."
        }.joined(separator: "\n\n")
    }()

    /// 3 tables (4 columns × 10 rows each).
    static let tablesOnly: String = {
        (1...3).map { tableIdx in
            let cols = 4
            let header = "| " + (1...cols).map { "Col\($0)" }.joined(separator: " | ") + " |"
            let sep = "| " + (1...cols).map { _ in "------" }.joined(separator: " | ") + " |"
            let rows = (1...10).map { row in
                "| " + (1...cols).map { "T\(tableIdx)R\(row)C\($0)" }.joined(separator: " | ") + " |"
            }.joined(separator: "\n")
            return header + "\n" + sep + "\n" + rows
        }.joined(separator: "\n\n")
    }()

    /// 20 thematic breaks (minimal cost baseline).
    static let thematicBreaksOnly: String = {
        (1...20).map { _ in "---" }.joined(separator: "\n\n")
    }()

    /// 12 standalone details blocks with summaries and short bodies.
    static let detailsOnly: String = {
        (1...12).map { idx in
            let openFlag = idx % 2 == 0 ? " open" : ""
            return """
            <details\(openFlag)>
            <summary>Summary \(idx)</summary>

            Body paragraph \(idx) with **bold** text.
            </details>
            """
        }.joined(separator: "\n\n")
    }()

    /// 12 diagram-only fenced blocks rotating supported languages.
    static let diagramsOnly: String = {
        let languages = ["mermaid", "geojson", "topojson", "stl"]
        return (1...12).map { idx in
            let language = languages[(idx - 1) % languages.count]
            switch language {
            case "mermaid":
                return "```mermaid\ngraph TD\nA\(idx) --> B\(idx)\n```"
            case "geojson":
                return "```geojson\n{ \"type\": \"Point\", \"coordinates\": [\(idx), \(idx + 1)] }\n```"
            case "topojson":
                return "```topojson\n{ \"type\": \"Topology\", \"objects\": { \"shape\": { \"type\": \"GeometryCollection\", \"geometries\": [] } } }\n```"
            default:
                return "```stl\nsolid s\(idx)\nendsolid\n```"
            }
        }.joined(separator: "\n\n")
    }()

    /// 120 standalone task-list items with mixed completion states.
    static let taskListsOnly: String = {
        (1...120).map { idx in
            let marker = idx.isMultiple(of: 4) ? "[x]" : "[ ]"
            return "- \(marker) Checklist item \(idx)"
        }.joined(separator: "\n")
    }()

    /// 24 block math formulas using `$$...$$` delimiters.
    static let mathBlocksOnly: String = {
        (1...24).map { idx in
            "$$\\int_0^{\(idx)} x^2 \\, dx = \\frac{\(idx)^3}{3}$$"
        }.joined(separator: "\n\n")
    }()

    /// Keyed collection for per-node-type iteration.
    static let nodeTypeFixtures: [(name: String, content: String)] = [
        ("headers", headersOnly),
        ("paragraphs", paragraphsOnly),
        ("code-blocks", codeBlocksOnly),
        ("unordered-lists", unorderedListsOnly),
        ("ordered-lists", orderedListsOnly),
        ("blockquotes", blockQuotesOnly),
        ("tables", tablesOnly),
        ("thematic-breaks", thematicBreaksOnly),
        ("details", detailsOnly),
        ("diagrams", diagramsOnly),
        ("task-lists", taskListsOnly),
        ("math-blocks", mathBlocksOnly),
    ]

    // MARK: - Scaling fixtures

    /// Generates a paragraph-heavy document of the specified line count.
    static func scalingFixture(lineCount: Int) -> String {
        var lines: [String] = []
        lines.append("# Scaling Test (\(lineCount) lines)")
        lines.append("")
        for idx in 1...lineCount {
            lines.append("Paragraph \(idx) with **bold**, *italic*, `code`, and a [link](https://example.com/\(idx)).")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static let scalingSizes: [Int] = [10, 50, 200, 1000]

    static let scalingFixtures: [(name: String, content: String)] = scalingSizes.map {
        ("\($0)-lines", scalingFixture(lineCount: $0))
    }
}
