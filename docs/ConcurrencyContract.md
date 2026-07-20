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
10. `MermaidSnapshotter` is `@MainActor` and owns Mermaid FIFO ordering, cache
    lookup/publication, cancellation, continuation resumption, and deadlines.
    Its default production backend is the file-backed `WKWebView` renderer. An
    internal factory can install a deterministic image driver before lazy
    singleton construction in iOS `@testable` tests; that driver replaces only
    source-to-image production, so the production queue/cache/cancellation state
    machine remains under test without constructing WebKit in an app-less XCTest
    process. Request identifiers reject late callbacks from older renders.
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
9. Keep the Mermaid test driver explicit and test-only: install it before the
   lazy snapshotter exists, and never select it through environment or runtime
   host detection in production.

## 3. Verification Coverage

1. `MarkdownRenderCoordinatorTests` covers single-flight no-overlap behavior, latest-request publication, parse-key/raw-AST reuse boundaries, and the details stale-configuration regression.
2. `MarkdownRenderInputTests` covers parse-key boundaries and layout-only dimensions (`width`, `theme`, `appearance`, diagram registry, image policy).
3. `GitHubAutolinkPluginTests` and `MarkdownKitTests` cover resolver forwarding, fallback destinations, resolver retention, fingerprinting, and detached parser construction/use.
4. `MermaidDiagramAdapterTests` validates source-cache reuse/isolation, fresh
   attachments, FIFO ordering, queued and active cancellation, and failure
   non-poisoning. macOS executes those contracts against the real `WKWebView`
   backend (including UTF-8 source preservation); iOS executes the same state
   machine against the deterministic injected image driver.
5. `MathWarningSuppressorTests` validates suppression actor semantics.
6. `SnapshotTests` and `DiagramSnapshotTests` validate end-to-end rendering stability.
7. `InlineFormattingLayoutTests` validates math fallback behavior when conversion fails.
8. `ConcurrencyStressTests` validates multi-task LayoutSolver/LayoutCache safety and parser thread safety.
9. `ImageResourceLoaderTests` validates policy, pre-follow redirect rejection, streamed byte limits, and response handling with injected `URLProtocol` responses plus local fixtures; it does not depend on the public network. `ImageAttachmentBuilderTests` validates bounded decode and cache isolation, while `InlineFormattingLayoutTests` verifies sync fallback cannot poison a later async attachment layout.
10. `scripts/verify_ios.sh` separately assembles the SwiftPM demo executable as
    a signed Simulator app and requires exactly one success marker after a
    Mermaid fence traverses public `MarkdownView` and a registry-backed real
    WebKit adapter inside the running SwiftUI application.

## 4. Known Limits and Host Responsibilities

1. `LayoutSolver` and helper types still rely on `@unchecked Sendable` boundaries and require disciplined call-site usage.
2. Multi-actor stress tests cover LayoutSolver, LayoutCache, and parser
   interleaving. The app-hosted iOS Mermaid gate is a one-render WebKit smoke
   contract, while macOS retains the deeper real-WebKit state-machine tests.
   Further stress of `DefaultMathRenderingAdapter` and WebKit process
   termination/reinitialization remains deferred.
3. Attachment upload, permalink/custom action, and issue-keyword workflow semantics have no renderer hooks; they are host/backend responsibilities outside MarkdownKit's parser/layout pipeline.
4. Markdown image support is inline-only. Changing `imageLoadingPolicy` starts a new layout/render generation and rebuilds attachments; there is no visible-cell or top-level image-loading executor.
