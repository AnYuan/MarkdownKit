# Asynchronous Layout Engine

## Overview
The `MarkdownKit` Layout Engine follows Texture-inspired separation between measurement and UI
mounting. It returns UI-detached `LayoutResult` values and is designed to be called off the main
actor; callers still choose the executor.

## Components

### `LayoutResult` 
An immutable, tree-structured model holding:
1. The exact bounding box (`CGSize`) for an element relative to a parent width constrain.
2. The pre-styled `NSAttributedString` generated from the `Theme`.
3. An array of children `LayoutResult` objects.

By keeping `LayoutResult` completely detached from UI layers (like `UIView` or `CALayer`), tree traversal and measurement can run in the background without touching UIKit/AppKit state. This describes the architecture, not a benchmarked bound on document size.

### `TextKitCalculator`
At its core, `TextKitCalculator` wraps Apple's new `TextKit 2` engine (using `NSTextLayoutManager`).
We inject the styled string and a mathematical width boundary `(e.g. 400pt wide)`, and `TextKit 2` generates the precise `usageBoundsForTextContainer` which corresponds to the exact pixel footprint the text will consume when rendered.

### `LayoutSolver`
A recursive tree solver. It visits an AST root (`DocumentNode`), applies the central `Theme` to create attributed strings, relies on `TextKitCalculator` to measure those strings, and packages them into `LayoutResult` trees.

### `LayoutCache`
An `NSCache`-backed memoization utility. 
Because text measurement is still expensive, `LayoutCache` keys results by node
`contentFingerprint`, an optional interaction fingerprint, rounded viewport width, and a
rendering-variant fingerprint. The interaction fingerprint invalidates cached callback payloads
when source ranges or source URLs change without changing semantic stable identity or pixel-render
identity. Collection views answer cell-size queries from already-computed `LayoutResult.size`; a
changed width, rendering variant, or visible interaction identity can require new layout work.
