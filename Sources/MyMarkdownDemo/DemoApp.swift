//
//  DemoApp.swift
//  MyMarkdownDemo
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import SwiftUI
import AppKit
import MyMarkdown

@main
struct DemoApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            DemoContentView()
                .frame(minWidth: 1100, minHeight: 700)
        }
    }
}

// MARK: - Main Content View

struct DemoContentView: View {
    @State private var selectedSyntax: SyntaxPage = .headers
    @State private var editableMarkdown: String = SyntaxPage.headers.source

    var body: some View {
        NavigationSplitView {
            List(SyntaxPage.allCases, id: \.self, selection: $selectedSyntax) { page in
                Label(page.title, systemImage: page.icon)
            }
            .navigationTitle("Syntax")
            .listStyle(.sidebar)
        } detail: {
            ThreePanelView(
                sourceMarkdown: selectedSyntax.source,
                editableMarkdown: $editableMarkdown
            )
        }
        .onChange(of: selectedSyntax) { _, newValue in
            editableMarkdown = newValue.source
        }
    }
}

// MARK: - Three-Panel Detail View

struct ThreePanelView: View {
    let sourceMarkdown: String
    @Binding var editableMarkdown: String
    @State private var renderTime: Double = 0
    @State private var isRendering: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Source")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                Text("Preview")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
                HStack {
                    Text("Editor")
                        .font(.caption.bold())
                    Spacer()
                    if isRendering {
                        ProgressView().scaleEffect(0.5)
                    } else if renderTime > 0 {
                        Text(String(format: "%.1fms", renderTime))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Three panels
            HSplitView {
                // Left: Source (read-only)
                SourcePanel(markdown: sourceMarkdown)
                    .frame(minWidth: 250)

                // Center: Preview (rendered)
                GeometryReader { geo in
                    MarkdownPreviewRep(
                        markdown: editableMarkdown,
                        width: geo.size.width,
                        renderTime: $renderTime,
                        isRendering: $isRendering
                    )
                }
                .frame(minWidth: 300)
                .background(Color(NSColor.textBackgroundColor))

                // Right: Editor (editable)
                EditorPanel(markdown: $editableMarkdown)
                    .frame(minWidth: 250)
            }
        }
    }
}

// MARK: - Source Panel (Read-Only)

struct SourcePanel: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Text(markdown)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - Editor Panel (Editable)

struct EditorPanel: View {
    @Binding var markdown: String

    var body: some View {
        TextEditor(text: $markdown)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)
    }
}

// MARK: - Preview (NSViewRepresentable)

struct MarkdownPreviewRep: NSViewRepresentable {
    let markdown: String
    let width: CGFloat
    @Binding var renderTime: Double
    @Binding var isRendering: Bool

    func makeNSView(context: Context) -> MarkdownCollectionView {
        MarkdownCollectionView()
    }

    func updateNSView(_ nsView: MarkdownCollectionView, context: Context) {
        guard width > 50 else { return }

        let currentMarkdown = markdown
        let currentWidth = width

        // Debounce: skip if same content and width
        let key = "\(currentMarkdown.hashValue)_\(Int(currentWidth))"
        if context.coordinator.lastKey == key { return }
        context.coordinator.lastKey = key

        Task {
            await MainActor.run { isRendering = true }

            let start = CFAbsoluteTimeGetCurrent()
            let parser = MarkdownParser(plugins: [MathExtractionPlugin()])
            let ast = parser.parse(currentMarkdown)
            let solver = LayoutSolver()
            let result = await solver.solve(node: ast, constrainedToWidth: currentWidth)
            let end = CFAbsoluteTimeGetCurrent()

            await MainActor.run {
                renderTime = (end - start) * 1000
                isRendering = false
                nsView.layouts = result.children
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastKey: String = ""
    }
}

// MARK: - Syntax Pages

enum SyntaxPage: String, CaseIterable, Hashable {
    case headers
    case paragraph
    case boldItalic
    case links
    case images
    case inlineCode
    case codeBlock
    case lists
    case taskLists
    case tables
    case math
    case blockquote

    var title: String {
        switch self {
        case .headers: return "Headers"
        case .paragraph: return "Paragraph"
        case .boldItalic: return "Bold & Italic"
        case .links: return "Links"
        case .images: return "Images"
        case .inlineCode: return "Inline Code"
        case .codeBlock: return "Code Block"
        case .lists: return "Lists"
        case .taskLists: return "Task Lists"
        case .tables: return "Tables"
        case .math: return "Math"
        case .blockquote: return "Blockquote"
        }
    }

    var icon: String {
        switch self {
        case .headers: return "textformat.size"
        case .paragraph: return "text.alignleft"
        case .boldItalic: return "bold.italic.underline"
        case .links: return "link"
        case .images: return "photo"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .codeBlock: return "curlybraces"
        case .lists: return "list.bullet"
        case .taskLists: return "checklist"
        case .tables: return "tablecells"
        case .math: return "function"
        case .blockquote: return "text.quote"
        }
    }

    // swiftlint:disable line_length
    var source: String {
        switch self {
        case .headers:
            return """
            # Heading Level 1
            ## Heading Level 2
            ### Heading Level 3
            #### Heading Level 4
            ##### Heading Level 5
            ###### Heading Level 6
            """

        case .paragraph:
            return """
            This is a simple paragraph of text. Markdown paragraphs are separated by blank lines.

            Here is a second paragraph. It can contain multiple sentences and will be wrapped automatically by the renderer.

            A third paragraph to demonstrate spacing between blocks.
            """

        case .boldItalic:
            return """
            This is **bold text** using double asterisks.

            This is *italic text* using single asterisks.

            This is ***bold and italic*** using triple asterisks.

            You can also use __underscores for bold__ and _underscores for italic_.
            """

        case .links:
            return """
            Visit [Apple](https://www.apple.com) for more info.

            Here is a [link with title](https://www.swift.org "Swift Language") that shows a tooltip.

            Multiple links: [Google](https://google.com), [GitHub](https://github.com), and [Stack Overflow](https://stackoverflow.com).
            """

        case .images:
            return """
            ![Swift Logo](https://swift.org/assets/images/swift.svg)

            ![Placeholder Image](https://via.placeholder.com/400x200)
            """

        case .inlineCode:
            return """
            Use `let x = 42` to declare a constant in Swift.

            The `print()` function outputs text to the console.

            Wrap code in single backticks like `NSAttributedString` for inline display.
            """

        case .codeBlock:
            return """
            ```swift
            struct MarkdownParser {
                func parse(_ text: String) -> DocumentNode {
                    let document = Document(parsing: text)
                    var visitor = MyMarkdownVisitor()
                    let nodes = visitor.defaultVisit(document)
                    return DocumentNode(range: nil, children: nodes)
                }
            }
            ```

            ```python
            def fibonacci(n):
                if n <= 1:
                    return n
                return fibonacci(n-1) + fibonacci(n-2)
            ```

            ```javascript
            const greet = (name) => {
                console.log(`Hello, ${name}!`);
            };
            ```
            """

        case .lists:
            return """
            Unordered list:
            - Apple
            - Banana
            - Cherry

            Ordered list:
            1. First item
            2. Second item
            3. Third item

            Nested list:
            - Fruits
              - Apple
              - Banana
            - Vegetables
              - Carrot
              - Broccoli
            """

        case .taskLists:
            return """
            - [x] Design the AST parser
            - [x] Implement LayoutSolver
            - [x] Build virtualized CollectionView
            - [ ] Add full math rendering
            - [ ] Write comprehensive tests
            """

        case .tables:
            return """
            | Feature | Status | Priority |
            |:--------|:------:|--------:|
            | Parsing | Done | High |
            | Layout | Done | High |
            | Rendering | WIP | Medium |
            | Math | Planned | Low |
            """

        case .math:
            return """
            Inline math: $E = mc^2$

            Block math:

            $$
            \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
            $$

            Another example: $\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}$
            """

        case .blockquote:
            return """
            > This is a blockquote. It can contain multiple lines of text.

            > Another quote with **bold** and *italic* text inside.

            Regular paragraph after the quotes.
            """
        }
    }
    // swiftlint:enable line_length
}
#endif
