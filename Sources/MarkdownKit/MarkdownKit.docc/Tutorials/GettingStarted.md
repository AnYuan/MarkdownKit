# Getting Started with MarkdownKit

Learn how to integrate responsive, off-main-thread Markdown rendering into your iOS and macOS apps.

## Overview

Unlike traditional web-view based renderers, MarkdownKit calculates sizes and text attributes asynchronously using native APIs (TextKit 2), then mounts components only as they enter the visible bounds of your `NSCollectionView` or `UICollectionView`.

### Basic Rendering Pipeline

1. **Parse**: Convert a raw markdown string into a native AST using `MarkdownParser`.
2. **Solve**: Pass the AST to `LayoutSolver.solve(node:constrainedToWidth:)` to compute sizes asynchronously.
3. **Display**: Update the `MarkdownCollectionView` with the resulting `[LayoutResult]` array.

```swift
let markdownString = "# Getting Started\nThis is a highly optimized engine."
let ast = MarkdownParser().parse(markdownString)

Task {
    // Solve layout on a background thread
    let layoutEngine = LayoutSolver()
    let layoutResult = await layoutEngine.solve(node: ast, constrainedToWidth: view.bounds.width)
    
    // Switch to main thread to instruct the CollectionView to render
    await MainActor.run {
        markdownCollectionView.layouts = [layoutResult]
    }
}
```

`MarkdownParser.parse(_:)` above is a lossy compatibility convenience: it logs diagnostics and
returns an empty (or partially-truncated) document instead of surfacing rejection. `MarkdownParser`
itself is synchronous and not `Sendable`, so keep a configured parser (and its plugins) confined
to a single task rather than sharing it across concurrent tasks; the example above stays on the
calling task until `parse(_:)` returns, then hops onto the `Task` for layout.

### Handling Untrusted Input

When rendering content you don't control (e.g. user-generated Markdown), inspect the typed
`parseOutcome(_:)` result instead of the lossy `parse(_:)` convenience:

```swift
let parser = MarkdownParser() // default limits: 1,048,576 UTF-8 bytes, 50 levels of AST-mapping recursion

switch parser.parseOutcome(untrustedMarkdown) {
case .parsed(let document, let diagnostics):
    // `diagnostics` may include `.maximumNestingDepthExceeded` if a deeply nested
    // subtree was truncated during native-AST mapping; the document is still usable.
    let layoutResult = await LayoutSolver().solve(node: document, constrainedToWidth: view.bounds.width)
case .rejected(let diagnostic):
    // Input's UTF-8 byte count exceeded `limits.maximumInputBytes` before any
    // swift-markdown parsing occurred.
    presentRejection(diagnostic)
}
```

`parseOutcome(_:)` never logs; it's the API to use when you need to distinguish rejected input
from a document that parsed successfully with no content, or need programmatic access to
diagnostics.

### Extending with Plugins

MarkdownKit’s AST is fully manipulable. You can write your own `ASTPlugin` to transform specific nodes before the layout engine calculates styling. For example, replacing a custom directive `::: info :::` into a custom stylized Quote block.

### Accessibility

MarkdownKit handles standard accessibility properties mapping automatically, but for customized interactive views, it leans on built-in Apple APIs. All virtualized blocks natively expose corresponding `UIAccessibilityElement` or `NSAccessibilityElement` roles to maintain VoiceOver purity.
