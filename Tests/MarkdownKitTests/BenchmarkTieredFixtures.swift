import Foundation

// swiftlint:disable type_body_length

/// 3-tier per-syntax fixtures: simple → complex → extreme.
/// Each syntax has 3 complexity levels to reveal performance degradation curves.
enum BenchmarkTieredFixtures {

    typealias TieredFixture = (
        syntax: String,
        tiers: [(tier: String, content: String)]
    )

    // MARK: - Header

    static let headerSimple = "# A Simple Header"

    static let headerComplex: String = {
        (1...5).map { idx in
            let level = ((idx - 1) % 3) + 1
            let hashes = String(repeating: "#", count: level)
            return "\(hashes) Header \(idx) **bold** *italic* [link](https://example.com)"
        }.joined(separator: "\n\n")
    }()

    static let headerExtreme: String = {
        (1...50).map { idx in
            let level = ((idx - 1) % 6) + 1
            let hashes = String(repeating: "#", count: level)
            return "\(hashes) Header \(idx) **bold** *italic* `code` [link](https://x.co/\(idx))"
        }.joined(separator: "\n\n")
    }()

    // MARK: - Paragraph

    static let paragraphSimple = "A simple paragraph with plain text content."

    static let paragraphComplex: String = {
        (1...5).map { idx in
            "Paragraph \(idx) with **bold**, *italic*, `code`, and a [link](https://example.com/\(idx))."
        }.joined(separator: "\n\n")
    }()

    static let paragraphExtreme: String = {
        (1...50).map { idx -> String in
            let base = "Paragraph \(idx) with **bold**, *italic*, `code`, ~~strikethrough~~."
            let extra = " More **nested *bold italic*** with `inline code` and [link](https://x.co/\(idx))."
            return base + extra
        }.joined(separator: "\n\n")
    }()

    // MARK: - Code Block

    static let codeBlockSimple: String = {
        let lines = (1...5).map { "let x\($0) = compute(\($0))" }
        return "```swift\n" + lines.joined(separator: "\n") + "\n```"
    }()

    static let codeBlockComplex: String = {
        ["swift", "python", "javascript"].map { lang in
            let lines = (1...30).map { "let val\($0) = compute(\($0))" }
            return "```\(lang)\n" + lines.joined(separator: "\n") + "\n```"
        }.joined(separator: "\n\n")
    }()

    static let codeBlockExtreme: String = {
        let langs = ["swift", "python", "javascript", "rust", "go",
                     "java", "ruby", "kotlin", "typescript", "cpp"]
        return langs.map { lang in
            let lines = (1...100).map { "let val\($0) = compute(\($0), f: 3)" }
            return "```\(lang)\n" + lines.joined(separator: "\n") + "\n```"
        }.joined(separator: "\n\n")
    }()

    // MARK: - Unordered List

    static let unorderedListSimple =
        "- Item one\n- Item two\n- Item three\n- Item four\n- Item five"

    static let unorderedListComplex: String = {
        (1...20).map { idx in
            var line = "- Item \(idx) with **bold** content"
            if idx % 3 == 0 {
                line += "\n  - Sub-item \(idx).1\n  - Sub-item \(idx).2"
            }
            return line
        }.joined(separator: "\n")
    }()

    static let unorderedListExtreme: String = {
        (1...50).map { idx in
            var lines = "- Item \(idx) **bold** *italic* `code`"
            lines += "\n  - Sub \(idx).1 with ~~strikethrough~~"
            lines += "\n    - Deep \(idx).1.1 nested content"
            lines += "\n      - Ultra \(idx).1.1.1 fourth level"
            return lines
        }.joined(separator: "\n")
    }()

    // MARK: - Ordered List

    static let orderedListSimple =
        "1. First step\n2. Second step\n3. Third step\n4. Fourth step\n5. Fifth step"

    static let orderedListComplex: String = {
        (1...20).map { idx in
            var line = "\(idx). Step \(idx) with **bold** and *italic*"
            if idx % 3 == 0 {
                line += "\n   1. Sub-step \(idx).1\n   2. Sub-step \(idx).2"
            }
            return line
        }.joined(separator: "\n")
    }()

    static let orderedListExtreme: String = {
        (1...50).map { idx in
            var lines = "\(idx). Step \(idx) **bold** *italic* `code`"
            lines += "\n   1. Sub \(idx).1 with ~~strikethrough~~"
            lines += "\n      1. Deep \(idx).1.1 nested content"
            lines += "\n         1. Ultra \(idx).1.1.1 fourth level"
            return lines
        }.joined(separator: "\n")
    }()

    // MARK: - Blockquote

    static let blockquoteSimple = "> A simple quoted statement."

    static let blockquoteComplex: String = {
        (1...5).map { idx -> String in
            let line1 = "> Quote \(idx) with **bold** and *italic* formatting."
            let line2 = "> Second line of quote \(idx) continues here."
            return line1 + "\n" + line2
        }.joined(separator: "\n\n")
    }()

    static let blockquoteExtreme: String = {
        (1...20).map { idx -> String in
            let line1 = "> Quote \(idx) with **bold**, *italic*, `code`."
            let line2 = "> > Nested quote \(idx) with ~~strikethrough~~."
            let line3 = "> > > Triple-nested for stress."
            return [line1, line2, line3].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }()

    // MARK: - Table

    static let tableSimple =
        "| Name | Value |\n|------|-------|\n| Alpha | 1 |\n| Beta | 2 |\n| Gamma | 3 |"

    static let tableComplex: String = {
        let cols = 5
        let header = (1...cols).map { "Col\($0)" }
        let headerRow = "| " + header.joined(separator: " | ") + " |"
        let sepRow = "| " + (1...cols).map { _ in "------" }.joined(separator: " | ") + " |"
        let rows = (1...15).map { row in
            let cells = (1...cols).map { "R\(row)C\($0) **bold**" }
            return "| " + cells.joined(separator: " | ") + " |"
        }.joined(separator: "\n")
        return headerRow + "\n" + sepRow + "\n" + rows
    }()

    static let tableExtreme: String = {
        let cols = 10
        let header = (1...cols).map { "Col\($0)" }
        let headerRow = "| " + header.joined(separator: " | ") + " |"
        let sepRow = "| " + (1...cols).map { _ in "------" }.joined(separator: " | ") + " |"
        let rows = (1...50).map { row in
            let cells = (1...cols).map { col in "R\(row)C\(col) **b** *i*" }
            return "| " + cells.joined(separator: " | ") + " |"
        }.joined(separator: "\n")
        return headerRow + "\n" + sepRow + "\n" + rows
    }()

    // MARK: - Thematic Break

    static let thematicBreakSimple = "---"

    static let thematicBreakComplex: String = {
        (1...10).map { _ in "---" }.joined(separator: "\n\n")
    }()

    static let thematicBreakExtreme: String = {
        (1...50).map { _ in "---" }.joined(separator: "\n\n")
    }()

    // MARK: - Inline Mix

    static let inlineMixSimple = "Text with **bold** only."

    static let inlineMixComplex: String = {
        (1...5).map { idx in
            "Sentence \(idx) with **bold**, *italic*, `code`, and [link](https://x.co/\(idx))."
        }.joined(separator: "\n\n")
    }()

    static let inlineMixExtreme: String = {
        (1...20).map { idx -> String in
            let part1 = "Sentence \(idx) has **bold *nested italic***"
            let part2 = " and ~~strikethrough~~ and `inline code`"
            let part3 = " and [link](https://x.co/\(idx)) and ***triple emphasis***."
            return part1 + part2 + part3
        }.joined(separator: "\n\n")
    }()

    // MARK: - Aggregated collection

    static let all: [TieredFixture] = [
        ("header", [
            ("simple", headerSimple),
            ("complex", headerComplex),
            ("extreme", headerExtreme)
        ]),
        ("paragraph", [
            ("simple", paragraphSimple),
            ("complex", paragraphComplex),
            ("extreme", paragraphExtreme)
        ]),
        ("code-block", [
            ("simple", codeBlockSimple),
            ("complex", codeBlockComplex),
            ("extreme", codeBlockExtreme)
        ]),
        ("unordered-list", [
            ("simple", unorderedListSimple),
            ("complex", unorderedListComplex),
            ("extreme", unorderedListExtreme)
        ]),
        ("ordered-list", [
            ("simple", orderedListSimple),
            ("complex", orderedListComplex),
            ("extreme", orderedListExtreme)
        ]),
        ("blockquote", [
            ("simple", blockquoteSimple),
            ("complex", blockquoteComplex),
            ("extreme", blockquoteExtreme)
        ]),
        ("table", [
            ("simple", tableSimple),
            ("complex", tableComplex),
            ("extreme", tableExtreme)
        ]),
        ("thematic-break", [
            ("simple", thematicBreakSimple),
            ("complex", thematicBreakComplex),
            ("extreme", thematicBreakExtreme)
        ]),
        ("inline-mix", [
            ("simple", inlineMixSimple),
            ("complex", inlineMixComplex),
            ("extreme", inlineMixExtreme)
        ])
    ]
}

// swiftlint:enable type_body_length
