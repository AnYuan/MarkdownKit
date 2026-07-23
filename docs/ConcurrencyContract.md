# MarkdownKit Concurrency Contract (2026-07-23)

This document defines the current thread/actor boundaries for parsing, layout, web rendering, host extension points, and UI mounting.

## 1. Isolation Boundaries

1. `MarkdownEngine` (`UI/SwiftUI/MarkdownRenderCoordinator.swift`) is the SwiftUI `@MainActor` coordinator boundary for request coalescing, cancellation, and publication. Its private, non-observable theme-fingerprint memoizer retains light/dark values only for the current `Theme`; body input construction and solver keying reuse the same value without crossing actors.
2. Coordinator single-flight rule: only one detached parse/layout task runs at a time, with only one latest pending request retained; newer requests replace older pending work.
3. Publication is generation-guarded (`output.generation == latestGeneration`), so canceled or stale completions never overwrite current `layouts`.
4. `MarkdownParser` is synchronous and intentionally non-`Sendable`; parser/plugin instances are constructed inside each detached render task and remain task-confined.
5. Raw AST reuse is bounded by `MarkdownParseKey` equality (`text`, `resourceLimits`, ordered plugin fingerprint). Width/theme/appearance/diagram/image-policy changes stay on the layout-only path.
6. Public `LayoutSolver.solve(node:constrainedToWidth:)` is async, intended for background execution, and remains a total-result API when its task is canceled. It yields once before work and then periodically across recursive solver nodes. A canceled public solve completes its resource sequence but publishes no new `LayoutCache` entries.
7. The SwiftUI coordinator alone uses internal `LayoutSolver.solveCancellable(...)`. One invocation-wide cooperation state checks cancellation between top-level children, one-child-at-a-time builder planning, materialization operations, and before/after resource work. It returns `nil` rather than a partial `LayoutResult`.
8. Cancellable solves stage cache misses in an invocation-local `LayoutCache.WriteBatch`; staged entries satisfy duplicate lookups and remain invisible to the shared cache until the complete root succeeds. Observed cancellation discards the batch. After the final cancellation check, synchronous child-before-parent commit is the point of no return: the solver returns the completed result without another cancellation check, and coordinator generation matching still prevents stale UI publication.
9. `LayoutSolver.solveSync(...)` is a fully synchronous cached + `buildStringSync` path; it does **not** dispatch detached async work. Sync and async layouts use distinct cache/render variants because sync images intentionally emit alt fallback instead of performing I/O.
10. Math rendering goes through `DefaultMathRenderingAdapter.render(from:theme:contextFont:)`. The adapter is `Sendable`; its `Engine` actor wraps `MathJaxSwift` for LaTeX → SVG conversion and `SwiftDraw` rasterization runs synchronously in the calling task.
11. `MathWarningSuppressor` is an actor that deduplicates noisy MathJax errors across concurrent renders.
12. `MermaidSnapshotter` is `@MainActor` and owns Mermaid FIFO ordering, cache
    lookup/publication, cancellation, continuation resumption, and deadlines.
    Its default production backend is the file-backed `WKWebView` renderer. An
    internal factory can install a deterministic image driver before lazy
    singleton construction in iOS `@testable` tests; that driver replaces only
    source-to-image production, so the production queue/cache/cancellation state
    machine remains under test without constructing WebKit in an app-less XCTest
    process. Request identifiers reject late callbacks from older renders.
13. Inline Markdown image work belongs to the layout task. `ImageResourceLoader.load` is `@concurrent`, rejects disallowed redirects before following them, streams remote bytes under the policy cap, and owns final-response validation plus typed rejection; `ImageAttachmentBuilder` synchronously decodes the returned bytes with ImageIO in the calling layout task.
14. `ImageAttachmentBuilder` stores decoded, width-constrained thumbnails in a thread-safe `NSCache` keyed by policy/source/rounded target width. Cache entries and each decoded image are bounded; canceled layout tasks do not publish new entries.
15. The internal `AsyncTextView` rasterizes attributed strings, including `NSTextAttachment` images, off-main; MarkdownKit's collection-view layer invokes `configure(with:)` from UI context and keeps final layer mounting UI-owned.
16. UI interactions (`onLinkTap`, checkbox/detail closures, platform gesture handlers) remain UI-owned and are executed from view layer contexts, not from parser/resolver callbacks.

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
10. Keep `LayoutCache.WriteBatch.commit()` synchronous and non-suspending. If a
    later design needs async publication, define a new ownership/rollback
    contract rather than adding an `await` inside the existing commit point.

## 3. Verification Coverage

1. `MarkdownRenderCoordinatorTests` covers theme-fingerprint memoization and
   invalidation, precomputed/direct solver-key reuse, real theme/appearance
   rerenders, single-flight no-overlap behavior, latest-request publication,
   parse-key/raw-AST reuse boundaries, the details stale-configuration
   regression, and a 1,000-diagram stale-layout handoff that proves only the
   first in-flight adapter call runs before the latest request takes over.
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
8. `ConcurrencyStressTests` validates multi-task LayoutSolver/LayoutCache safety, parser thread safety, serialized cold CoreText/TextKit fallback work, recursive attachment-driven re-entry, and oversized-token slice checkpoints. `DiagramLayoutTests` separately locks public total-result cancellation, coordinator-cancellable resource short-circuiting, staged-cache rollback, staged duplicate reuse, and successful child/root publication.
9. `ImageResourceLoader` owns one reusable delegate transport per loader. Concurrent tasks are isolated by URL-session task identifier; response headers are validated before body acceptance, and Foundation-delivered `Data` chunks are checked before append against the configured cap. Cancellation claims one terminal continuation, cancels the underlying task, and ignores late callbacks. `ImageResourceLoaderTests` validates these contracts with injected `URLProtocol` responses plus local fixtures and does not depend on the public network. `ImageAttachmentBuilderTests` validates bounded decode and cache isolation, while `InlineFormattingLayoutTests` verifies sync fallback cannot poison a later async attachment layout.
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
5. Cancellation is cooperative. Synchronous highlighting, measurement, decoding,
   and custom adapter implementations cannot be preempted while running; a
   canceled coordinator solve stops at the first checkpoint after that in-flight
   work or await returns. Arithmetic line breaking checks between prepared chunks
   and oversized-token slices, but a cold unique oversized token is synchronously
   shaped as a complete token under the global CoreText safety gate;
   `solveCancellable` cannot observe cancellation until the enclosing
   `prepare(...)` returns.
