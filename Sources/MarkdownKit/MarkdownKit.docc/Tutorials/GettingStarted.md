# Getting Started with MarkdownKit

Learn the supported ways to parse, lay out, and render MarkdownKit content in iOS and macOS apps.

## Overview

MarkdownKit is centered on native parsing plus off-main layout. Prefer ``MarkdownKitEngine`` for app code, use ``MarkdownParser`` and ``LayoutSolver`` explicitly when you need pipeline control, and inspect typed parse outcomes for untrusted content. ``MarkdownView`` is the primary SwiftUI rendering surface; direct ``MarkdownCollectionView`` use is an advanced integration path for host-owned virtualization.

### One-call Layout

Use ``MarkdownKitEngine/layout(markdown:constrainedToWidth:parser:solver:appearance:)`` when you need a single immutable ``LayoutResult`` tree.

```swift
import MarkdownKit

let layout = await MarkdownKitEngine.layout(
    markdown: "# Getting Started\nThis is a native MarkdownKit layout.",
    constrainedToWidth: 640
)

print(layout.children.count)
```

Direct layout APIs use `.light` appearance by default. Pass `appearance: .dark` or a custom solver when you need deterministic dark output.

### Explicit Parser and Solver

Use explicit construction when you need custom plugins, a shared cache, theme selection, diagram adapters, math adapters, or image-loading policy.

```swift
import MarkdownKit

let parser = MarkdownKitEngine.makeParser(
    includeGitHubAutolinks: true
)
let solver = MarkdownKitEngine.makeLayoutSolver(
    theme: .default,
    imageLoadingPolicy: .remoteHTTPS
)

let document = parser.parse(markdownString)
let layout = await solver.solve(node: document, constrainedToWidth: 640)
```

`parse(_:)` is a lossy compatibility convenience: it logs diagnostics and returns an empty or partially truncated document instead of surfacing rejection. Keep configured parser/plugin instances task-confined; plugins are not required to be `Sendable`.

### Resource Limits and Typed Outcomes

For untrusted or unbounded content, inspect ``MarkdownParser/parseOutcome(_:)`` and configure ``MarkdownParser/ResourceLimits`` for the host surface.

```swift
import MarkdownKit

let parser = MarkdownKitEngine.makeParser(
    resourceLimits: .init(maximumInputBytes: 1_000_000, maximumNestingDepth: 50)
)

switch parser.parseOutcome(untrustedMarkdown) {
case .parsed(let document, let diagnostics):
    let layout = await MarkdownKitEngine.makeLayoutSolver().solve(
        node: document,
        constrainedToWidth: 640
    )
    render(layout, diagnostics: diagnostics)
case .rejected(let diagnostic):
    presentRejection(diagnostic)
}
```

The input byte limit is enforced before `swift-markdown` parsing. The nesting-depth limit bounds only native-AST mapping, not layout depth.

### SwiftUI Rendering

SwiftUI hosts must import SwiftUI explicitly; MarkdownKit does not re-export it.

```swift
import MarkdownKit
import SwiftUI

struct MarkdownArticleView: View {
    let markdown: String

    var body: some View {
        MarkdownView(
            text: markdown,
            imageLoadingPolicy: .remoteHTTPS
        )
        .textInteractionMode(.selectableNative)
        .onLinkTap { url in
            open(url)
        }
        .onCheckboxToggle { checkbox in
            updateTask(isChecked: checkbox.isChecked)
        }
    }
}
```

``MarkdownView`` coordinates parse/layout work with cancellation, reuses layout caches while inputs stay compatible, follows the SwiftUI color scheme, and keeps UI interactions in host-owned callbacks.

### Advanced Collection View Integration

Use ``MarkdownCollectionView`` directly only when you own the UIKit/AppKit container and want to feed precomputed layouts yourself.

```swift
import MarkdownKit
import UIKit

let collectionView = MarkdownCollectionView(frame: view.bounds)
collectionView.textInteractionMode = .asyncReadOnly
collectionView.layouts = layout.children
```

On macOS, import AppKit instead of UIKit. Keep UIKit/AppKit mutation on the main actor and keep sizing O(1) by using precomputed ``LayoutResult/size`` values.

### Extending the Pipeline

Write ``ASTPlugin`` implementations for AST rewrites, register ``DiagramRenderingAdapter`` values with ``DiagramAdapterRegistry``, inject ``MathRenderingAdapter`` implementations into ``LayoutSolver``, and customize output with ``Theme``, ``TypographyToken``, ``ColorToken``, ``MarkdownAppearance``, and ``ImageLoadingPolicy``. See <doc:PublicAPI> for the supported surface.
