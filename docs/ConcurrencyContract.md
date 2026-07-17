# MarkdownKit Concurrency Contract (2026-07-17)

This document defines the current thread/actor boundaries for parsing, layout, web rendering, host extension points, and UI mounting.

## 1. Isolation Boundaries

1. `MarkdownEngine` (`UI/SwiftUI/MarkdownRenderCoordinator.swift`) is the SwiftUI `@MainActor` coordinator boundary for request coalescing, cancellation, and publication.
2. Coordinator single-flight rule: only one detached parse/layout task runs at a time, with only one latest pending request retained; newer requests replace older pending work.
3. Publication is generation-guarded (`output.generation == latestGeneration`), so canceled or stale completions never overwrite current `layouts`.
4. `MarkdownParser` is synchronous and intentionally non-`Sendable`; parser/plugin instances are constructed inside each detached render task and remain task-confined.
5. Raw AST reuse is bounded by `MarkdownParseKey` equality (`text`, `resourceLimits`, ordered plugin fingerprint). Width/theme/appearance/diagram/image-policy changes stay on the layout-only path.
6. `LayoutSolver.solve(node:constrainedToWidth:)` is async and intended for background execution.
7. `LayoutSolver.solveSync(...)` is a fully synchronous cached + `buildStringSync` path; it does **not** dispatch detached async work.
8. Math rendering goes through `DefaultMathRenderingAdapter.render(from:theme:contextFont:)`. The adapter is `Sendable`; its `Engine` actor wraps `MathJaxSwift` for LaTeX → SVG conversion and `SwiftDraw` rasterization runs synchronously in the calling task.
9. `MathWarningSuppressor` is an actor that deduplicates noisy MathJax errors across concurrent renders.
10. `MermaidSnapshotter` is `@MainActor` and serializes all `WKWebView` rendering via an internal FIFO queue.
11. `AsyncImageView` performs data loading and decode in `Task.detached`, then mounts `layer.contents` on `MainActor`.
12. `AsyncTextView` may rasterize text off-main; callers must still invoke `configure(with:)` from UI context.
13. UI interactions (`onLinkTap`, checkbox/detail closures, platform gesture handlers) remain UI-owned and are executed from view layer contexts, not from parser/resolver callbacks.

## 2. Rules for New Code

1. Keep `WKWebView` lifecycle and JavaScript evaluation on `MainActor`.
2. Avoid sharing mutable renderer state across tasks unless wrapped in an actor.
3. Any detached background task must marshal final UIKit/AppKit mutations back to main.
4. If a method is intentionally cross-actor, document the contract at declaration.
5. Preserve deterministic ordering for queued render operations (diagram/math pipelines and SwiftUI render coordinator requests).
6. If resolver output affects rendered links, include that state in `cacheFingerprint(into:)`.
7. The deprecated `MarkdownContextDelegate` name is only a migration spelling; conformers still must satisfy `MarkdownAutolinkResolver`'s `Sendable` contract.

## 3. Verification Coverage

1. `MarkdownRenderCoordinatorTests` covers single-flight no-overlap behavior, latest-request publication, parse-key/raw-AST reuse boundaries, and the details stale-configuration regression.
2. `MarkdownRenderInputTests` covers parse-key boundaries and layout-only dimensions (`width`, `theme`, `appearance`, diagram registry, image policy).
3. `GitHubAutolinkPluginTests` and `MarkdownKitTests` cover resolver forwarding, fallback destinations, resolver retention, fingerprinting, and detached parser construction/use.
4. `MermaidDiagramAdapterTests` validates Mermaid snapshot pipeline behavior.
5. `MathWarningSuppressorTests` validates suppression actor semantics.
6. `SnapshotTests` and `DiagramSnapshotTests` validate end-to-end rendering stability.
7. `InlineFormattingLayoutTests` validates math fallback behavior when conversion fails.
8. `ConcurrencyStressTests` validates multi-task LayoutSolver/LayoutCache safety and parser thread safety.

## 4. Known Limits and Host Responsibilities

1. `LayoutSolver` and helper types still rely on `@unchecked Sendable` boundaries and require disciplined call-site usage.
2. Multi-actor stress tests now cover LayoutSolver, LayoutCache, and parser interleaving. Further coverage of `DefaultMathRenderingAdapter` and `MermaidSnapshotter` concurrent usage is deferred.
3. Attachment upload, permalink/custom action, and issue-keyword workflow semantics have no renderer hooks; they are host/backend responsibilities outside MarkdownKit's parser/layout pipeline.
