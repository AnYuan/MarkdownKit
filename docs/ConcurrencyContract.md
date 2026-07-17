# MarkdownKit Concurrency Contract (2026-07-17)

This document defines the current thread/actor boundaries for parsing, layout, web rendering, host extension points, and UI mounting.

## 1. Isolation Boundaries

1. `MarkdownEngine` (`UI/SwiftUI/MarkdownRenderCoordinator.swift`) is the SwiftUI `@MainActor` coordinator boundary for request coalescing, cancellation, and publication.
2. Coordinator single-flight rule: only one detached parse/layout task runs at a time, with only one latest pending request retained; newer requests replace older pending work.
3. Publication is generation-guarded (`output.generation == latestGeneration`), so canceled or stale completions never overwrite current `layouts`.
4. `MarkdownParser` is synchronous and intentionally non-`Sendable`; parser/plugin instances are constructed inside each detached render task and remain task-confined.
5. Raw AST reuse is bounded by `MarkdownParseKey` equality (`text`, `resourceLimits`, ordered plugin fingerprint). Width/theme/appearance/diagram/image-policy changes stay on the layout-only path.
6. `LayoutSolver.solve(node:constrainedToWidth:)` is async and intended for background execution.
7. `LayoutSolver.solveSync(...)` is a fully synchronous cached + `buildStringSync` path; it does **not** dispatch detached async work. Sync and async layouts use distinct cache/render variants because sync images intentionally emit alt fallback instead of performing I/O. Canceled async solves do not publish layout-cache entries.
8. Math rendering goes through `DefaultMathRenderingAdapter.render(from:theme:contextFont:)`. The adapter is `Sendable`; its `Engine` actor wraps `MathJaxSwift` for LaTeX → SVG conversion and `SwiftDraw` rasterization runs synchronously in the calling task.
9. `MathWarningSuppressor` is an actor that deduplicates noisy MathJax errors across concurrent renders.
10. `MermaidSnapshotter` is `@MainActor` and serializes all `WKWebView`
    rendering via an internal FIFO queue. Cache lookup occurs only when a
    request reaches the queue head; successful intrinsic images are retained in
    a bounded source cache, while failed or canceled requests cannot publish
    entries. Request identifiers reject late callbacks from older renders.
11. Inline Markdown image work belongs to the layout task. `ImageResourceLoader.load` is `@concurrent`, rejects disallowed redirects before following them, streams remote bytes under the policy cap, and owns final-response validation plus typed rejection; `ImageAttachmentBuilder` synchronously decodes the returned bytes with ImageIO in the calling layout task.
12. `ImageAttachmentBuilder` stores decoded, width-constrained thumbnails in a thread-safe `NSCache` keyed by policy/source/rounded target width. Cache entries and each decoded image are bounded; canceled layout tasks do not publish new entries.
13. The internal `AsyncTextView` rasterizes attributed strings, including `NSTextAttachment` images, off-main; MarkdownKit's collection-view layer invokes `configure(with:)` from UI context and keeps final layer mounting UI-owned.
14. UI interactions (`onLinkTap`, checkbox/detail closures, platform gesture handlers) remain UI-owned and are executed from view layer contexts, not from parser/resolver callbacks.

## 2. Rules for New Code

1. Keep `WKWebView` lifecycle and JavaScript evaluation on `MainActor`.
2. Avoid sharing mutable renderer state across tasks unless wrapped in an actor.
3. Any detached background task must marshal final UIKit/AppKit mutations back to main.
4. If a method is intentionally cross-actor, document the contract at declaration.
5. Preserve deterministic ordering for queued render operations (diagram/math pipelines and SwiftUI render coordinator requests).
6. If resolver output affects rendered links, include that state in `cacheFingerprint(into:)`.
7. The deprecated `MarkdownContextDelegate` name is only a migration spelling; conformers still must satisfy `MarkdownAutolinkResolver`'s `Sendable` contract.
8. Preserve the unified inline image boundary: do not add source resolution, network/file loading, redirect checks, or independent image caches to UI cells.

## 3. Verification Coverage

1. `MarkdownRenderCoordinatorTests` covers single-flight no-overlap behavior, latest-request publication, parse-key/raw-AST reuse boundaries, and the details stale-configuration regression.
2. `MarkdownRenderInputTests` covers parse-key boundaries and layout-only dimensions (`width`, `theme`, `appearance`, diagram registry, image policy).
3. `GitHubAutolinkPluginTests` and `MarkdownKitTests` cover resolver forwarding, fallback destinations, resolver retention, fingerprinting, and detached parser construction/use.
4. `MermaidDiagramAdapterTests` validates source-cache reuse/isolation, fresh
   attachments, FIFO ordering, queued and active cancellation, failure
   non-poisoning, and real `WKWebView` render counts.
5. `MathWarningSuppressorTests` validates suppression actor semantics.
6. `SnapshotTests` and `DiagramSnapshotTests` validate end-to-end rendering stability.
7. `InlineFormattingLayoutTests` validates math fallback behavior when conversion fails.
8. `ConcurrencyStressTests` validates multi-task LayoutSolver/LayoutCache safety and parser thread safety.
9. `ImageResourceLoaderTests` validates policy, pre-follow redirect rejection, streamed byte limits, and response handling with injected `URLProtocol` responses plus local fixtures; it does not depend on the public network. `ImageAttachmentBuilderTests` validates bounded decode and cache isolation, while `InlineFormattingLayoutTests` verifies sync fallback cannot poison a later async attachment layout.

## 4. Known Limits and Host Responsibilities

1. `LayoutSolver` and helper types still rely on `@unchecked Sendable` boundaries and require disciplined call-site usage.
2. Multi-actor stress tests cover LayoutSolver, LayoutCache, and parser
   interleaving; real-WebView Mermaid tests cover serialized cache/cancellation
   behavior. Further stress of `DefaultMathRenderingAdapter` and WebKit process
   termination/reinitialization remains deferred.
3. Attachment upload, permalink/custom action, and issue-keyword workflow semantics have no renderer hooks; they are host/backend responsibilities outside MarkdownKit's parser/layout pipeline.
4. Markdown image support is inline-only. Changing `imageLoadingPolicy` starts a new layout/render generation and rebuilds attachments; there is no visible-cell or top-level image-loading executor.
