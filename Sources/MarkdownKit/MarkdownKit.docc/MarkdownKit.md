# ``MarkdownKit``

A high-performance, extensibility-first, Apple-native Markdown rendering engine.

## Overview

MarkdownKit renders Markdown through a supported public pipeline: parse Markdown into
MarkdownKit nodes, solve immutable layout results off the main actor, and mount those
results through SwiftUI or an advanced platform collection view integration. The parser
uses explicit resource limits for untrusted input, while plugins and adapters let hosts
customize autolinks, diagrams, math, and theming without depending on implementation
details.

Use the highest-level workflow that fits your app:

### One-call layout

```swift
import MarkdownKit

let layout = await MarkdownKitEngine.layout(
    markdown: "## Hello World",
    constrainedToWidth: 400
)
```

### Explicit parser and solver

```swift
import MarkdownKit

let parser = MarkdownKitEngine.makeParser()
let solver = MarkdownKitEngine.makeLayoutSolver(theme: .default)
let document = parser.parse("## Hello World")
let layout = await solver.solve(node: document, constrainedToWidth: 400)
```

### Typed outcomes for untrusted input

```swift
import MarkdownKit

let parser = MarkdownKitEngine.makeParser(
    resourceLimits: .init(maximumInputBytes: 1_000_000, maximumNestingDepth: 50)
)

switch parser.parseOutcome(untrustedMarkdown) {
case .parsed(let document, let diagnostics):
    let layout = await MarkdownKitEngine.makeLayoutSolver().solve(
        node: document,
        constrainedToWidth: 400
    )
    handle(layout, diagnostics)
case .rejected(let diagnostic):
    handleRejection(diagnostic)
}
```

### SwiftUI rendering

```swift
import MarkdownKit
import SwiftUI

struct ArticleView: View {
    let markdown: String

    var body: some View {
        MarkdownView(text: markdown)
            .textInteractionMode(.selectableNative)
    }
}
```

For low-level host-owned virtualization, use ``MarkdownCollectionView`` directly as an
advanced integration surface after producing ``LayoutResult`` values.

## Topics

### Public API
- <doc:PublicAPI>

### Core Workflows
- ``MarkdownKitEngine``
- ``MarkdownParser``
- ``LayoutSolver``
- ``LayoutResult``

### SwiftUI
- ``MarkdownView``
- ``MarkdownTextInteractionMode``

### Theming and Resources
- ``Theme``
- ``TypographyToken``
- ``ColorToken``
- ``MarkdownAppearance``
- ``ImageLoadingPolicy``

### Advanced Extensions
- ``ASTPlugin``
- ``MarkdownAutolinkResolver``
- ``GitHubAutolinkPlugin``
- ``DiagramAdapterRegistry``
- ``DiagramRenderingAdapter``
- ``MermaidDiagramAdapter``
- ``MathRenderingAdapter``
- ``DefaultMathRenderingAdapter``
- ``MarkdownCollectionView``
- ``LayoutCache``
- ``PerformanceProfiler``
