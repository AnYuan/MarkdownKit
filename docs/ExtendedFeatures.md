# ChatGPT Parity Extended Features

To reach full feature parity with ChatGPT's sophisticated rendering application, the `MyMarkdown` engine integrates several advanced modules beyond standard CommonMark layout.

## 1. Syntax Highlighting (Splash)
Instead of relying on heavy JavaScript-based libraries (like `highlight.js`) embedded inside web views, the engine natively parses code strings using [Splash](https://github.com/JohnSundell/Splash). 
- `SplashHighlighter` acts as a middleware mapping `Theme.codeColor` components to Splash's internal lexer format.
- Operations run entirely on a background thread during `LayoutSolver` routines.

## 2. LaTeX Math Rendering (MathJax SVG)
Native Swift doesn't inherently understand `$\frac{1}{2}$`.
- We use `MathJaxSwift` (JavaScriptCore) via `MathRenderer` to convert LaTeX into SVG without relying on a network CDN.
- A shared hidden `WKWebView` is used only for SVG rasterization to produce native image attachments.
- The rasterized result is wrapped into `NSTextAttachment` and inserted into the TextKit 2 layout pipeline.
- `MathExtractionPlugin` normalizes both `$...$`/`$$...$$` and fenced math blocks (e.g. ````math`) into `MathNode`.
- Inline extraction includes guardrails for escaped literal-dollar edge cases and unmatched delimiters.

## 3. GitHub Flavored Markdown (GFM) Tables
Rendering tables inside virtualized CollectionViews is notoriously complex. Building CollectionView grids inside CollectionView cells breaks virtual scrolling performance.
- We render tables using native `NSTextTable`/`NSTextTableBlock` attributes so TextKit draws real cell borders and header backgrounds.
- `LayoutSolver` converts `TableNode` rows/cells into text-table blocks, preserving per-column alignment from GFM (`left/center/right`).
- Cell styling (padding, border, header background) is tokenized via `Theme.tableColor`, keeping a GitHub-like look while remaining fully native.

## 4. Native Actions (Copy/Paste)
The `AsyncCodeView` component introduces OS-level actions overlaying the asynchronous rendering layer. A native `UIButton` (iOS) or `NSButton` (macOS) sits atop the background canvas, injecting the raw AST `.code` string directly into the system pasteboard (`UIPasteboard`) upon tap, complete with animation state polling.
- Code blocks with language identifiers now render a compact uppercase language label (`SWIFT`, `PYTHON`, etc.) above highlighted content.

## 5. Dynamic Theme Transitions
When OS-level appearances change (e.g. User transitions from Light to Dark mode), evaluating dynamic colors captured within the `NSAttributedString` object cache must be violently purged.
`MarkdownCollectionViewThemeDelegate` safely delegates `traitCollectionDidChange` signals for instantaneous foreground invalidation and background re-computation without leaking memory.

## 6. GitHub-Style Collapsed Sections (`<details>/<summary>`)
- `DetailsExtractionPlugin` converts raw HTML details syntax into dedicated `DetailsNode` and `SummaryNode` models, preserving optional `open` state.
- `MyMarkdownVisitor` now retains `HTMLBlock` content as `TextNode` so details tags are not dropped during AST conversion.
- `LayoutSolver` renders summary rows with disclosure indicators (`▶` closed / `▼` open), and conditionally renders the body only when expanded.
- Demo app pipeline now chains `Details + Diagram + Math` plugins so collapsed sections, diagram fences, and math syntax coexist in one pass.

## 7. Diagram Fence Detection and Adapter Fallback
- `DiagramExtractionPlugin` upgrades fenced code blocks with languages `mermaid`, `geojson`, `topojson`, and `stl` into dedicated `DiagramNode`.
- Host apps can register custom `DiagramRenderingAdapter` implementations through `DiagramAdapterRegistry`.
- `LayoutSolver` first asks the adapter for rendered output; if unavailable, it falls back to code-block rendering with language label and syntax highlighting.
- Demo app pipeline now includes `DiagramExtractionPlugin`, so diagram fences are recognized out of the box.
