# Public API Surface

Use these surfaces as MarkdownKit's supported consumer and extension API before 1.0. Implementation details outside this list may change without source compatibility.

## Stable Consumer Workflows

- ``MarkdownKitEngine`` for default plugins, parser/solver construction, and one-call layout.
- ``MarkdownParser`` typed outcomes and ``MarkdownParser/ResourceLimits`` for trusted and untrusted parsing.
- ``LayoutSolver`` and immutable ``LayoutResult`` values for off-main measurement and host rendering.
- ``MarkdownView`` with ``MarkdownTextInteractionMode``, `onLinkTap(_:)`, and `onCheckboxToggle(_:)` for SwiftUI hosts.
- ``Theme``, ``TypographyToken``, ``ColorToken``, and ``MarkdownAppearance`` for styling and deterministic light/dark layout.
- ``ImageLoadingPolicy`` for explicit opt-in image loading.

## Advanced Extension Workflows

- ``MarkdownAutolinkResolver`` with ``GitHubAutolinkPlugin`` for host-specific mentions, references, and commits. Deprecated `MarkdownContextDelegate` names and `contextDelegate:` labels are retained only as migration shims.
- ``ASTPlugin``, ``AST``, ``ASTRewrite``, public node model types, and built-in extraction plugins for AST rewrites.
- ``DiagramRenderingAdapter``, ``DiagramAdapterRegistry``, ``DiagramLanguage``, and ``MermaidDiagramAdapter`` for diagram rendering.
- ``MathRenderingAdapter`` and ``DefaultMathRenderingAdapter`` for math rendering.
- ``MarkdownCollectionView`` and ``MarkdownCollectionViewThemeDelegate`` for advanced UIKit/AppKit virtualization.
- ``LayoutCache`` sharing when hosts intentionally reuse compatible layout inputs.
- ``PerformanceProfiler`` for measuring host integrations.

## Implementation-Only Boundaries

MarkdownKit owns the swift-markdown visitor, URL sanitizer, text calculators and syntax
highlighter, native-image aliases, table-of-contents helper, raw layout-cache operations,
theme fingerprint helpers, hosted platform cells/views, accessibility projection, and diffable
identity. These symbols are intentionally not exported.

``LayoutResult`` publicly exposes only its render payload: node, size, attributed string,
children, custom drawing closure, and appearance. Stable diff identity, render fingerprints,
and cached accessibility metadata are computed and managed inside MarkdownKit.

## Imports

SwiftUI hosts must explicitly import SwiftUI alongside MarkdownKit. MarkdownKit does not re-export SwiftUI. Splash is an internal syntax-highlighting dependency and is not re-exported or part of the supported public API.
