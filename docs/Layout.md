# Asynchronous Layout Engine

## Overview
The `MarkdownKit` Layout Engine follows Texture-inspired separation between measurement and UI
mounting. It returns UI-detached `LayoutResult` values and is designed to be called off the main
actor; callers still choose the executor.

## Components

### `LayoutResult` 
An immutable, tree-structured model holding:
1. The exact bounding box (`CGSize`) for an element relative to a parent width constraint.
2. The pre-styled `NSAttributedString` generated from the `Theme`.
3. An array of children `LayoutResult` objects.

By keeping `LayoutResult` completely detached from UI layers (like `UIView` or `CALayer`), tree traversal and measurement can run in the background without touching UIKit/AppKit state. This describes the architecture, not a benchmarked bound on document size.

### `TextKitCalculator`
The internal `TextKitCalculator` uses the platform's TextKit 1
`NSLayoutManager`/`NSTextContainer` pipeline so measurement matches the hosted text renderers.
It applies the styled string and width boundary (for example, 400 points) and reports the used
layout bounds.

### Arithmetic text pipeline
The internal `ArithmeticTextCalculator` remains the pure-text routing and prepared-cache facade.
Width-independent preparation is split into internal value types:
`ArithmeticTextScanner` streams raw UTF-16 boundaries without buffering spans,
`ArithmeticTextSegmentClassifierMerger` applies localized word boundaries and sticky-token merge
rules, and `ArithmeticTextMeasurer` resolves platform fonts, line metrics, cached segment widths,
and the aligned `PreparedText` payload.

`ArithmeticTextLineBreaker` consumes that width-independent payload for each viewport width, preserving separate fit and paint advances, paragraph indents, hard breaks, discretionary soft hyphens, and CoreText grapheme fallback for oversized tokens. Unsupported scripts and attachment-bearing strings continue to route through `TextKitCalculator`.

### `LayoutSolver`
A recursive tree solver. After cache lookup, it classifies each node into a shallow recipe, applies the central `Theme`, measures the output, and packages it into `LayoutResult` trees. Public async solving remains total when its task is canceled and replaces per-node yielding with one initial yield plus bounded periodic solver yields. The SwiftUI coordinator uses a separate internal cancellable envelope that returns no partial tree and stops between children, planning work, materialization operations, and resource boundaries. The sync envelope remains fully synchronous.

### `AttributedStringBuilder`
The builder expands block and inline structure into an invocation-local flat operation program. Its stack advances one structural child at a time so coordinator-cancellable planning has a bounded checkpoint without duplicating block/inline dispatch. Sequential async and sync materializers consume the same structural program; image loading, math rendering, and diagram rendering remain explicit mode-specific leaves. Cancellable materialization discards an in-flight resource result if cancellation was observed before it returned and never starts the next resource.

### Table layout
`TableLayoutShared` is the single owner of canonical table content and uniform column geometry. It rectangularizes ragged compatible `TableNode` input into immutable rows/cells with display text, alignment, header/body role, and body-row index, then sanitizes width inputs before producing per-platform geometry.

Rendering remains intentionally platform-specific through thin adapters: macOS emits native `NSTextTableBlock` content with zebra styling; nested UIKit attributed rendering uses tab stops or a narrow pipe fallback with zebra styling; top-level UIKit layout uses `TableCardRenderer` to measure wrapped theme-configured text (13pt by default) and draw a rounded `CGContext` card with borders/dividers and no zebra. `LayoutSolver` preserves the UIKit top-level contract by returning `customDraw` with a nil attributed string.

### `LayoutCache`
An `NSCache`-backed memoization utility. 
Because text measurement is still expensive, `LayoutCache` keys results by node
`contentFingerprint`, an optional interaction fingerprint, rounded viewport width, and a
rendering-variant fingerprint. The interaction fingerprint invalidates cached callback payloads
when source ranges or source URLs change without changing semantic stable identity or pixel-render
identity. Collection views answer cell-size queries from already-computed `LayoutResult.size`; a
changed width, rendering variant, or visible interaction identity can require new layout work.
Coordinator-cancellable solves stage cache misses in an invocation-local write batch. Staged
entries serve duplicate nodes during that solve, are discarded if cancellation is observed, and
commit child-before-parent only after the complete root result succeeds.
