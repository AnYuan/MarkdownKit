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

    /// All fixtures for iteration.
    static let allFixtures: [(name: String, content: String)] = [
        ("small", small),
        ("medium", medium),
        ("large", large),
        ("code-heavy", codeHeavy),
        ("table-heavy", tableHeavy),
        ("math-heavy", mathHeavy),
    ]
}
