# Rendering Pipeline Sequence

This sequence shows the end-to-end flow from markdown input to on-screen virtualized rendering.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Demo as "DemoApp / Preview"
    participant Parser as "MarkdownParser"
    participant Visitor as "MarkdownKitVisitor"
    participant Plugin as "ASTPlugin Chain"
    participant Solver as "LayoutSolver"
    participant Cache as "LayoutCache"
    participant Highlight as "SplashHighlighter"
    participant Math as "DefaultMathRenderingAdapter (MathJax → SwiftDraw)"
    participant ImageBuilder as "ImageAttachmentBuilder"
    participant ImageLoader as "ImageResourceLoader"
    participant Measure as "TextKitCalculator"
    participant CV as "MarkdownCollectionView"
    participant Cell as "MarkdownCollectionViewCell"
    participant TextView as "AsyncTextView"
    participant CodeView as "AsyncCodeView"

    User->>Demo: Edit / load markdown text
    Demo->>Parser: parse(markdown)
    Parser->>Visitor: visit swift-markdown AST
    Visitor-->>Parser: [MarkdownNode]
    Parser->>Plugin: run plugins (e.g. MathExtractionPlugin)
    Plugin-->>Parser: transformed nodes
    Parser-->>Demo: DocumentNode

    Demo->>Solver: solve(document, width)
    Solver->>Cache: getLayout(node, width)
    alt Cache hit
        Cache-->>Solver: LayoutResult
    else Cache miss
        Solver->>Solver: createAttributedString(node)
        opt Code block
            Solver->>Highlight: highlight(code)
            Highlight-->>Solver: attributed code
        end
        opt Math node
            Solver->>Math: render(latex)
            Math-->>Solver: image attachment / fallback
        end
        opt Inline ImageNode
            Solver->>ImageBuilder: build(source, policy, width)
            ImageBuilder->>ImageLoader: resolve + redirect-gated byte stream
            ImageLoader-->>ImageBuilder: validated bytes / typed rejection
            ImageBuilder->>ImageBuilder: ImageIO thumbnail + decoded cache
            ImageBuilder-->>Solver: NSTextAttachment / bracketed alt fallback
        end
        Solver->>Measure: calculateSize(attributedString, width)
        Measure-->>Solver: CGSize
        Solver->>Cache: setLayout(result, width)
    end
    Solver-->>Demo: LayoutResult tree

    Demo->>CV: layouts = result.children
    CV->>Cell: dequeue + configure(layout)
    alt Text-like node
        Cell->>TextView: configure(layout)
        TextView->>TextView: background text rasterization
        TextView-->>Cell: layer.contents update on MainActor
    else Code block
        Cell->>CodeView: configure(layout)
        CodeView->>TextView: configure(inset layout)
    end
```

## Notes

- Sizing is expected to be O(1) at collection-view query time because dimensions are precomputed.
- Heavy work is intentionally shifted to background tasks, with only final layer/content mounting on main thread.
- Theme/appearance changes should trigger layout refresh so cached attributed output matches current colors.
- Markdown images are inline attachments built during layout. Image-policy changes relayout and rebuild attachments; collection-view cells never start image I/O.
- The pipeline does not produce top-level/block-image rows.
