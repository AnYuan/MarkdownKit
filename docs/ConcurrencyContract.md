# MarkdownKit Concurrency Contract (2026-03-04)

This document defines the current thread/actor boundaries for parsing, layout, web rendering, and UI mounting.

## 1. Isolation Boundaries

1. `LayoutSolver.solve(node:constrainedToWidth:)` is async and intended for background execution.
2. `LayoutSolver.solveSync(...)` blocks the caller and dispatches detached async work; use only when async call sites are impossible.
3. `AttributedStringBuilder.renderMath(...)` always hops to `MainActor` before calling `MathRenderer.shared.render(...)`.
4. `MathRenderer` uses internal actors (`Engine`, `MathWarningSuppressor`) for shared-state safety and serializes WebKit usage through a single queue.
5. `MermaidSnapshotter` is `@MainActor` and serializes all `WKWebView` rendering via an internal FIFO queue.
6. `AsyncImageView` performs data loading and decode in `Task.detached`, then mounts `layer.contents` on `MainActor`.
7. `AsyncTextView` may rasterize text off-main; callers must still invoke `configure(with:)` from UI context.

## 2. Rules for New Code

1. Keep `WKWebView` lifecycle and JavaScript evaluation on `MainActor`.
2. Avoid sharing mutable renderer state across tasks unless wrapped in an actor.
3. Any detached background task must marshal final UIKit/AppKit mutations back to main.
4. If a method is intentionally cross-actor, document the contract at declaration.
5. Preserve deterministic ordering for queued render operations (diagram/math pipelines).

## 3. Verification Coverage

1. `MermaidDiagramAdapterTests` validates Mermaid snapshot pipeline behavior.
2. `MathWarningSuppressorTests` validates suppression actor semantics.
3. `SnapshotTests` and `DiagramSnapshotTests` validate end-to-end rendering stability.
4. `InlineFormattingLayoutTests` validates math fallback behavior when conversion fails.

## 4. Known Limits

1. `LayoutSolver` and helper types still rely on `@unchecked Sendable` boundaries and require disciplined call-site usage.
2. Multi-actor stress tests for parser/layout/render interleaving are not yet comprehensive.
