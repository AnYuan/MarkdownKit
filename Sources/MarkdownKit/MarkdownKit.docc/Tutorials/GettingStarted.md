# Getting Started with MarkdownKit

Learn how to integrate zero-latency Markdown rendering into your iOS and macOS apps.

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

### Extending with Plugins

MarkdownKit’s AST is fully manipulable. You can write your own `ASTPlugin` to transform specific nodes before the layout engine calculates styling. For example, replacing a custom directive `::: info :::` into a custom stylized Quote block.

### Accessibility

MarkdownKit handles standard accessibility properties mapping automatically, but for customized interactive views, it leans on built-in Apple APIs. All virtualized blocks natively expose corresponding `UIAccessibilityElement` or `NSAccessibilityElement` roles to maintain VoiceOver purity.
