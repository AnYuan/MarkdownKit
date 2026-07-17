# AST Parsing Engine

## Overview
`MarkdownParser` is the supported consumer entry point for turning Markdown text into MarkdownKit's native `MarkdownNode` tree.
It owns the public parsing workflow: input-size checks, `swift-markdown` front-end parsing, native node mapping, optional plugin execution, and typed diagnostics.

## Public entry point: `MarkdownParser`
Use `MarkdownParser` when you need a `DocumentNode`:

```swift
let parser = MarkdownParser()
let document = parser.parse(markdown)
```

When you need typed diagnostics, use `parseOutcome(_:)` instead:

```swift
let parser = MarkdownParser(
    limits: .init(maximumInputBytes: 1_048_576, maximumNestingDepth: 50)
)

switch parser.parseOutcome(markdown) {
case .parsed(let document, let diagnostics):
    print(document.children.count)
    print(diagnostics)
case .rejected(let diagnostic):
    print(diagnostic)
}
```

### Resource limits and outcomes
- `ResourceLimits.maximumInputBytes` rejects oversized input before `swift-markdown` parsing begins.
- `ResourceLimits.maximumNestingDepth` bounds MarkdownKit's native-AST mapping recursion. If the boundary is reached, the boundary container remains in the mapped tree while omitted descendants are reported through `.maximumNestingDepthExceeded`.
- `ParseOutcome` preserves the difference between a rejected input and a successfully parsed document with diagnostics. `parse(_:)` is the compatibility convenience when callers only want a `DocumentNode`.

## Native node model
Every visible block or inline element is converted into a structurally safe `MarkdownNode`.
This avoids exposing consumers to `swift-markdown`'s raw syntax tree during layout and rendering, and keeps later pipeline stages working on immutable Swift value types such as `DocumentNode`, `ParagraphNode`, and `HeaderNode`.

## Internal implementation detail: `MarkdownKitVisitor`
After `swift-markdown` produces a `Document`, MarkdownKit uses the internal `MarkdownKitVisitor` struct to traverse that syntax tree and map it into `[MarkdownNode]`.
Consumers should not construct the visitor directly or depend on raw `swift-markdown` traversal as part of MarkdownKit's supported API surface.
