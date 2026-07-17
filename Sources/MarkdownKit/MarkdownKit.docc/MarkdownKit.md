# ``MarkdownKit``

A high-performance, extensibility-first, Apple-native Markdown rendering engine.

## Overview

MarkdownKit is built for responsive native Markdown rendering with an explicit, conservative
resource policy rather than an unmeasured "any size document" promise. High-level rendering
surfaces schedule parse and layout work off the main actor; the low-level parser itself is
synchronous. A plugin architecture lets developers transform the native MarkdownKit AST and
build rich, interactive UI components directly into standard text flows.

It supports GitHub Flavored Markdown (GFM), including tables, interactive task lists, and code blocks, as well as extended elements like LaTeX math and Mermaid diagrams.

### Getting Started

To get started with MarkdownKit, simply initialize the parser and provide it to the layout engine:

```swift
import MarkdownKit

let parser = MarkdownParser()
let document = parser.parse("## Hello World")

let layoutSolver = LayoutSolver(theme: .default)
let result = await layoutSolver.solve(node: document, constrainedToWidth: 400)
```

`parser.parse(_:)` is a lossy compatibility convenience: it logs diagnostics and returns an
empty (or partially-truncated) document rather than surfacing rejection. When parsing untrusted
content, call `parser.parseOutcome(_:)` instead and inspect its `.rejected`/`.parsed(document:
diagnostics:)` cases directly — it never logs on its own. `MarkdownParser` enforces a default
`ResourceLimits` of 1,048,576 UTF-8 bytes (`maximumInputBytes`) and 50 levels of native-AST
mapping recursion (`maximumNestingDepth`); the depth budget bounds only the mapping of an
already-parsed `swift-markdown` tree into MarkdownKit's native nodes, not `swift-markdown`
parsing itself or layout depth. The root document is not counted; a boundary container remains
while its descendants are omitted. `MarkdownParser` is synchronous and not `Sendable` (its
plugins need not be `Sendable`), so confine a parser instance to a single task rather than
sharing it across concurrent tasks.

## Topics

### Core Types
- ``MarkdownParser``
- ``LayoutSolver``
- ``LayoutResult``

### Plugins & Adapters
- ``ASTPlugin``
- ``DiagramAdapterRegistry``
- ``DiagramRenderingAdapter``
- ``MermaidDiagramAdapter``

### User Interface
- ``MarkdownCollectionView``
- ``MarkdownItemView``

### Customization
- ``Theme``
- ``TypographyToken``
- ``ColorToken``
