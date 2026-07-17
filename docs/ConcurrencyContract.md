# MarkdownKit Concurrency Contract (2026-03-04)

This document defines the current thread/actor boundaries for parsing, layout, web rendering, host extension points, and UI mounting.

## 1. Isolation Boundaries

1. `MarkdownParser` is synchronous and intentionally non-`Sendable`; parser/plugin instances are task-confined and must not be shared across concurrent tasks.
2. `MarkdownAutolinkResolver` is `AnyObject & Sendable` with synchronous mention/reference/commit methods. Resolvers may be invoked off-main during detached render work, so use immutable state or explicit synchronization rather than a main-actor UI object.
3. `GitHubAutolinkPlugin` strongly retains its optional resolver and fingerprints nil-vs-resolver configuration plus resolver-owned fingerprint state. A resolver must not retain the parser/plugin graph and create a cycle.
4. `LayoutSolver.solve(node:constrainedToWidth:)` is async and intended for background execution.
5. `LayoutSolver.solveSync(...)` blocks the caller and dispatches detached async work; use only when async call sites are impossible.
6. Math rendering goes through `DefaultMathRenderingAdapter.render(from:theme:contextFont:)`. The adapter is `Sendable`; its `Engine` actor wraps `MathJaxSwift` for LaTeX → SVG conversion and `SwiftDraw` rasterization runs synchronously in the calling task.
7. `MathWarningSuppressor` is an actor that deduplicates noisy MathJax errors across concurrent renders.
8. `MermaidSnapshotter` is `@MainActor` and serializes all `WKWebView` rendering via an internal FIFO queue.
9. `AsyncImageView` performs data loading and decode in `Task.detached`, then mounts `layer.contents` on `MainActor`.
10. `AsyncTextView` may rasterize text off-main; callers must still invoke `configure(with:)` from UI context.
11. UI interactions (`onLinkTap`, checkbox/detail closures, platform gesture handlers) remain UI-owned and are executed from view layer contexts, not from parser/resolver callbacks.

## 2. Rules for New Code

1. Keep `WKWebView` lifecycle and JavaScript evaluation on `MainActor`.
2. Avoid sharing mutable renderer state across tasks unless wrapped in an actor.
3. Any detached background task must marshal final UIKit/AppKit mutations back to main.
4. If a method is intentionally cross-actor, document the contract at declaration.
5. Preserve deterministic ordering for queued render operations (diagram/math pipelines).
6. If resolver output affects rendered links, include that state in `cacheFingerprint(into:)`.
7. The deprecated `MarkdownContextDelegate` name is only a migration spelling; conformers still must satisfy `MarkdownAutolinkResolver`'s `Sendable` contract.

## 3. Verification Coverage

1. `GitHubAutolinkPluginTests` and `MarkdownKitTests` cover resolver forwarding, fallback destinations, resolver retention, fingerprinting, and detached parser construction/use.
2. `MermaidDiagramAdapterTests` validates Mermaid snapshot pipeline behavior.
3. `MathWarningSuppressorTests` validates suppression actor semantics.
4. `SnapshotTests` and `DiagramSnapshotTests` validate end-to-end rendering stability.
5. `InlineFormattingLayoutTests` validates math fallback behavior when conversion fails.
6. `ConcurrencyStressTests` validates multi-task LayoutSolver/LayoutCache safety and parser thread safety.

## 4. Known Limits and Host Responsibilities

1. `LayoutSolver` and helper types still rely on `@unchecked Sendable` boundaries and require disciplined call-site usage.
2. Multi-actor stress tests now cover LayoutSolver, LayoutCache, and parser interleaving. Further coverage of `DefaultMathRenderingAdapter` and `MermaidSnapshotter` concurrent usage is deferred.
3. Attachment upload, permalink/custom action, and issue-keyword workflow semantics have no renderer hooks; they are host/backend responsibilities outside MarkdownKit's parser/layout pipeline.
