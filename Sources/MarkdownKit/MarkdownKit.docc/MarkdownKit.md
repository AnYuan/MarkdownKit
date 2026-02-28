# ``MarkdownKit``

A high-performance, extensibility-first, Apple-native Markdown rendering engine.

## Overview

MarkdownKit is built from the ground up for zero-UI-blocking performance when parsing and rendering massive multi-megabyte markdown files. It seamlessly integrates a robust plugin architecture allowing developers to extend Apple's `swift-markdown` abstract syntax tree (AST) and build rich, interactive UI components directly into standard text flows.

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
