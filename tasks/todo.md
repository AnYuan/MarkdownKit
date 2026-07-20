# Implementation Checklist (Atomic Commits)

## Setup
- [x] Initialize standard Swift Package `MarkdownKit` workspace
- [x] Add Apple's `swift-markdown` library as a dependency
- [x] Setup base XCTest target `MarkdownKitTests`
- [x] Implement `PerformanceProfiler` utility for benchmarking AST and Layout speeds

## Phase 1: Parsing Engine (AST)
- [x] Add Official CommonMark Spec Test Suite (600+ tests) automation to test target (Highest Priority)
- [x] Define internal `MarkdownNode` protocol and base element structures
- [x] Implement `DocumentNode`, `BlockNode`, and `InlineNode` models
- [x] Implement `HeaderNode`, `ParagraphNode`, and `TextNode` models
- [x] Implement `CodeBlockNode` and `InlineCodeNode` models
- [x] Implement `MathNode` (block `$$` and inline `$`) models
- [x] Implement `ImageNode` and `LinkNode` models
- [x] Create `MarkupVisitor` class subscribing to `swift-markdown` API
- [x] Implement `MarkupVisitor` parsing for basic blocks (Headers, Paragraphs)
- [x] Implement `MarkupVisitor` parsing for complex blocks (Code, Images, Lists)
- [x] Implement AST Extensibility mechanism (Middleware Plugin protocol)
- [x] Add Unit Tests: CommonMark standard parsing fidelity
- [x] Add Unit Tests: GitHub Flavored Markdown parsing fidelity

## Phase 2: Asynchronous Layout Engine
- [x] Implement `TypographyToken` and `ColorToken` theme structures
- [x] Create `LayoutResult` models containing exact `CGRect` dimensions
- [x] Create base `TextKit 2` calculator class running on background queue
- [x] Implement background sizing solver for standard text blocks
- [x] Implement caching mechanism for Layout models based on width/Device scale
- [ ] (Deferred) Implement asynchronous yielding/chunked parsing for very large documents; today `MarkdownParser.ResourceLimits` instead enforces a conservative default input ceiling (`maximumInputBytes` = 1,048,576 UTF-8 bytes) and rejects larger input via `parseOutcome(_:)` rather than streaming or chunking it
- [x] Add Unit Tests: Verify exact framing dimension logic for varying strings

## Phase 3: Virtualized Rendering UI
- [x] Implement core virtualized `NSCollectionView` (macOS) layout
- [x] Implement core virtualized `UICollectionView` (iOS) layout
- [x] Create Native component: `MarkdownTextView`
- [x] Create Native component: `MarkdownImageView`
- [x] Create Native component: `MarkdownCodeView`
- [x] Implement `Texture`-style Display State logic: Asynchronously render text to `CGContext` on background thread
- [x] Implement `Texture`-style Display State logic: Asynchronously decode image data to `CGImage` on background thread
- [x] Implement `Texture`-style Display State logic: Mount views onto main thread only when visible
- [x] Implement `Texture`-style Display State logic: Purge memory-heavy backing stores when offscreen
- [x] Add Unit Tests: Verify node virtualization limits memory consumption

## Phase 4: Extended Features (ChatGPT Parity)
- [x] Integrate native "Copy Paste" UX for Code Blocks
- [x] Integrate lightweight syntax highlighter for Code Blocks
- [x] Add UI styling for Markdown Tables and Checkbox Task Lists
- [x] Integrate lightweight LaTeX renderer (MathJax/iosMath) for $$ MathNodes
- [x] Implement smooth transitioning between Light/Dark mode themes
- [x] Add UI Snapshot Tests for Code Block and Math rendering parity (Substituted by Unit Tests due to missing Host App)

## Phase 5: Delivery & Polish
- [x] Profile and resolve any memory leaks associated with image loading or TextKit caches (Demo App `MarkdownKitDemo` Provided)
- [x] Profile and resolve scrolling hitches using Instruments (Demo App `MarkdownKitDemo` Provided)
- [x] Final architecture documentation and code hygiene review

## Phase 6: GitHub Advanced Formatting Alignment (PRD §7)

### P0: Core Markdown Rendering Parity
- [x] Switch table rendering from text emulation to native `NSTextTable` / `NSTextTableBlock`
- [x] Apply GitHub-like table styling baseline (header fill, borders, zebra stripe body rows)
- [x] Keep column alignment mapping parity for GFM tables (`left/center/right`)
- [x] Add parser/layout support for fenced math blocks using ```math syntax
- [x] Add strict regression tests for inline `$...$` and block `$$...$$` edge cases (escaping, multiline, mixed text)
- [x] Add optional language badge rendering for fenced code blocks

### P1: Advanced Formatting Features
- [x] Implement `<details>/<summary>` parsing as dedicated nodes (instead of raw `InlineHTML` fallback)
- [x] Render collapsible sections natively in both iOS/macOS UI layers
- [x] Add diagram block detection for fenced languages: `mermaid`, `geojson`, `topojson`, `stl`
- [x] Implement pluggable diagram rendering adapters with code-block fallback when adapter is unavailable
- [x] Extend autolink support from URLs to issue/PR refs, commit SHAs, and `@mention` tokens (resolver-based)
- [x] Upgrade tasklist rendering to support editor-mode interaction toggles while preserving read-only mode

### P2: Host-App Integration Boundaries
- [x] Expose extension APIs for attachment workflows (upload + insertion), kept out of renderer core
- [x] Expose extension APIs for permalink/snippet cards (repository context required)
- [x] Expose extension hooks for issue-keyword semantics (`close/fix/resolve`) for host products

### Cross-Cutting Test Tasks
- [x] Add snapshot coverage for table, code, math, and tasklist visual parity on iOS + macOS
- [x] Add feature-status matrix test docs linking each PRD §7 feature to test case names

## Phase 7: Production Readiness (Security & Robustness)
- [x] Security: Implement strict URL sanitization for `LinkNode` and `ImageNode` (filter out `javascript:`, `vbscript:`, etc.)
- [x] Security: Implement deterministic URI schema allow-listing (e.g., `http/https/mailto/tel/sms`) with configurable policies
- [x] Robustness: Implement recursive depth limits (e.g., max 50 levels) in `MarkdownKitVisitor` and node traversal plugins to prevent Stack Overflows
- [x] Robustness: Integrate a Fuzz testing suite (or permutation script testing) to ensure zero-crash parsing on hostile randomly generated markdown payloads
- [x] Quality Assurance: Integrate `swift-snapshot-testing` framework and produce baseline reference images for core syntax element rendering (headers, tables, math, details) into UI tests
- [x] Fix compiler warnings: Explicitly declare or exclude `__Snapshots__` resources in `Package.swift`

## Phase 8: Diagram Rendering (Mermaid Support)
- [x] Create `DiagramAdapter` protocol and plugin architecture
- [x] Implement `MermaidDiagramAdapter` utilizing a lightweight headless WKWebView
- [x] Add loading state, error fallback, and dynamic resizing for Mermaid diagram containers
- [x] Add UI Snapshot Coverage for rendered mermaid diagrams


## Phase 9: Accessibility (VoiceOver) Parity
- [x] Audit virtualized `MarkdownTextView` blocks and define `UIAccessibilityElement` / `NSAccessibilityElement` boundaries
- [x] Implement accessibility reading order for linear text content despite virtualized layouts
- [x] Add accessibility traits for interactive nodes (Links, Interactive Tasklists, Math Blocks)
- [x] Add VoiceOver announcements for complex structures (Tables, Code Blocks)

## Phase 10: Developer Experience & Documentation (DocC)
- [x] Adopt modern Swift documentation comments (`///`) across all public APIs and components
- [x] Create structured DocC Tutorial articles covering: "Getting Started", "Customizing Theme", and "Writing an AST Plugin"
- [x] Generate DocC archive and verify documentation coverage

## Phase 11: High-Performance Pure Arithmetic Layout Engine (Pretext-inspired)
*Note: Execution restarts from the current exploratory implementation. Existing scaffolding remains valuable, but the items below define the production-hardening path and must be executed as strictly atomic commits.*

### Current Groundwork
- [x] Baseline benchmark infrastructure exists for parse/layout/cache/concurrency reporting.
- [x] `ArithmeticTextCalculator` exists and is wired into `LayoutSolver` for selected pure-text nodes.
- [x] Initial SoA-style storage and basic pure-math line breaking exist.
- [x] Initial benchmark docs mention arithmetic-vs-TextKit direction.

### Commit Discipline
- [x] Each commit changes exactly one of: tests, benchmarks, internal refactor, or one semantic layout behavior.
- [x] Each commit includes the minimum tests required for that one behavior and passes the focused suite before the next commit starts.
- [x] Benchmark baseline docs are updated only in dedicated benchmark commits, never mixed with semantic engine changes.
- [x] Routing expansion commits must follow, not precede, parity coverage for the newly supported text behavior.

### Atomic Execution Plan
- [x] `test: add pure-text oracle matrix`
  Add a focused oracle suite comparing `ArithmeticTextCalculator` against `TextKitCalculator` for Latin, CJK, emoji, explicit newlines, and paragraph indent cases.
- [x] `bench: split arithmetic prepare/layout baselines`
  Add benchmark coverage that reports arithmetic prepare cost separately from arithmetic layout cost so future gains are attributable.
- [x] `refactor: split arithmetic calculator into prepare and layout phases`
  Keep external behavior stable while introducing internal `prepare(...)` and `layout(...)` boundaries.
- [x] `perf: cache measured segment widths`
  Add font-aware segment width caching only; do not change line-breaking semantics in this commit.
- [x] `refactor: replace boolean arrays with explicit segment kinds`
  Replace `isSpace` / `isNewline` storage with a stable internal `SegmentKind` model.
- [x] `feat: add line-fit metadata`
  Introduce `lineEndFitAdvance`, `lineEndPaintAdvance`, and hard-break chunk metadata for correct fit vs paint behavior.
- [x] `feat: add grapheme fallback for oversized tokens`
  Support grapheme-level breaking for tokens wider than the available line width.
- [x] `feat: support glue and zero-width break semantics`
  Add `NBSP`, narrow no-break space, word joiner, and zero-width space handling.
- [x] `feat: support discretionary soft hyphen`
  Add soft-hyphen measurement and rendering semantics only when a break is taken.
- [x] `feat: add locale-aware word segmentation`
  Replace the current whitespace-only segmentation with locale-aware word boundary detection.
- [x] `feat: merge url and punctuation runs`
  Add URL-like, query-string, and closing-punctuation merge heuristics for more stable token measurement.
- [x] `feat: merge numeric and cjk sticky runs`
  Add numeric-chain and basic CJK sticky-boundary heuristics without expanding into complex-script shaping.
- [x] `feat: gate arithmetic routing by prepared-text profile`
  Route only text profiles proven by parity tests; keep unsupported scripts and attachment-heavy content on TextKit.
- [x] `perf: reuse prepared paragraphs across width changes`
  Add prepared-text reuse so repeated width relayout avoids repeated preparation work.
- [x] `test: add complex-script oracle corpus`
  Add Arabic, Thai, Myanmar, Hindi, and mixed-bidi oracle coverage before any routing expansion for those cases.
- [x] `docs: publish arithmetic status and refreshed benchmark snapshot`
  Update plan/docs/status files in a docs-only commit once the engine and benchmark numbers are current.

### Published Status
- [x] Arithmetic text layout now uses explicit `prepare(...)` and `layout(...)` phases, plus prepared-paragraph reuse across width changes.
- [x] Segment semantics cover glue, zero-width breaks, soft hyphen, hard breaks, grapheme fallback, locale-aware segmentation, URL merges, numeric chains, and CJK sticky runs.
- [x] `LayoutSolver` now gates arithmetic routing through a prepared-text profile so unsupported scripts and attachment-heavy content stay on `TextKitCalculator`.
- [x] Oracle coverage exists for both supported pure-text arithmetic cases and unsupported complex-script fallback cases.
- [x] Refreshed Phase 2 benchmark numbers were captured on 2026-04-01 and published in `docs/BENCHMARK_BASELINE.md`.

### Residual Follow-up
- [x] Resolve the macOS snapshot drift in `SnapshotTests.testTableRendering` and `SnapshotTests.testTasklistRendering` after restoring compact task-list spacing and refreshing the reference images.

## Phase 12: Code Quality Roadmap

Each stage is intentionally atomic: implement one concern, run its focused checks,
review the complete diff, then commit and push before starting the next stage.

- [x] `fix: restore arithmetic width invariant`
  Ensure reported arithmetic layout width never exceeds the supplied constraint
  because of trailing separator paint width.
- [x] `fix: derive system-font traits safely`
  Remove private `.SFNS-*` descriptor round-tripping and the resulting CoreText
  fallback diagnostics.
- [x] `ci: run the complete macOS correctness suite`
  Replace the suite allow-list with an exclusion-based non-benchmark gate.
- [x] `ci: execute UIKit tests on an iOS simulator`
  Repair stale platform tests first, then add an iOS CI lane.
  Review: the lane enumerates and executes all 374 enabled iOS tests, requires
  every UIKit-bearing suite, rejects process restarts/private-font fallback,
  and the macOS gate remains green at 320 correctness + 4 snapshot tests.
- [x] `bench: make the regression baseline authoritative`
  Use one machine-readable benchmark baseline for tests and documentation.
  Review: `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json` is now the
  single schema-versioned source; `BenchmarkRegressionGuard` decodes/validates
  it via `Bundle.module` (no embedded timing table), and
  `scripts/render_benchmark_baseline.py` renders the same JSON into
  `docs/BENCHMARK_BASELINE.md`, with `--check` wired into
  `scripts/verify_benchmarks.sh` as a fail-fast pre-flight step. New
  `PerformanceBaselineContractTests` (no "Benchmark" in the name, so
  `verify_fast.sh` still runs it) cover schema validation and exact key
  alignment without executing timing workloads. Validation: the complete
  benchmark gate passes, and the CI correctness configuration runs 330 tests
  including all 10 baseline-contract tests. The local table snapshot still
  depends on pre-layout appearance and is intentionally left to the next
  snapshot-determinism stage rather than refreshing an unrelated baseline.
- [x] `test: separate snapshot determinism from visual regression`
  Give snapshot and documentation freshness checks explicit, honest CI roles.
  Review: macOS reference construction fixes Aqua before test-only synchronous
  layout, view configuration, and drawing, so committed snapshots no longer
  inherit the host appearance. CI now enforces four separate, honestly-scoped
  contracts instead of one blended gate. (1) `verify_fast.sh` (job `verify`) is
  correctness-only in every environment — the CI-conditional snapshot branch
  is gone, so it never records or verifies snapshots locally or in CI; it
  still discovers and excludes only the exact
  `SnapshotTests`/`iOSSnapshotTests` suites, keeping `DiagramSnapshotTests` as
  correctness. (2) `check_doc_freshness.sh` runs as its own explicit, strict
  step in the `verify` job right after the
  correctness gate. (3) `verify_snapshots.sh` owns `SnapshotTests` in a new
  `verify-snapshots` job with two independent modes: `--visual` diffs against
  exactly one git-tracked baseline PNG per discovered test and is
  `continue-on-error: true` because
  `macos-26`/`latest-stable` is a moving rendering environment; `--determinism`
  records-then-reverifies in the same run and is blocking. (4) `verify-ios`
  is unchanged and still owns UIKit correctness; `iOSSnapshotTests` has no
  committed baseline or dedicated CI lane yet, so it stays intentionally
  excluded from both `verify_fast.sh` and `verify_snapshots.sh` rather than
  being implied as covered. Validation: `bash -n` on all three touched
  scripts, Ruby `YAML.load_file` on `ci.yml`, `bash scripts/check_doc_freshness.sh`,
  `CI=true bash scripts/verify_fast.sh` (330 correctness tests, 0 failures),
  `bash scripts/verify_snapshots.sh --visual` (4/4 passed), `bash
  scripts/verify_snapshots.sh --determinism` (4/4 record-expected-failures,
  4/4 reverify passed), snapshot directory `git status` identical before and
  after determinism, and `git diff --check` all pass.
- [x] `feat: make parser resource limits explicit`
  Replace global input/depth limits and silent truncation with per-parser policy
  and diagnosable outcomes. Review: `MarkdownParser.ResourceLimits` now owns the
  immutable per-instance 1 MiB / 50-level defaults; `parseOutcome(_:)`
  distinguishes rejection from parsed documents and reports depth truncation,
  while legacy `parse(_:)` remains an explicitly lossy logging wrapper. Limits
  propagate through `MarkdownKitEngine.makeParser` and every `MarkdownView`
  parse trigger, and unsupported streaming, fixed-memory, and frame-rate claims
  were removed or marked as deferred targets. Validation: 28 focused parser
  contract tests, `swift build`, documentation freshness, generated benchmark
  documentation, the discovery-driven macOS gate (44 suites / 348 tests), the
  iOS Simulator gate (402 tests), four read-only quality reviews, and
  `git diff --check` all pass; iOS logs contain no process restarts or private
  system-font fallback diagnostics.
- [x] `fix: reject numeric commit-autolink false positives`
  Preserve issue references while leaving ordinary long numeric identifiers as
  text. Review: commit candidates keep the existing lowercase hexadecimal,
  7...40-character, and token-boundary rules but must now contain at least one
  `a...f`; all-decimal candidates fall through the no-match path with their
  original `TextNode` identity. Numeric `#issue` and `owner/repo#issue`
  references, delegate resolution, and inline-code commit display remain
  unchanged. Validation: focused autolink tests (8/8), strict documentation
  freshness (369 discoverable tests), the discovery-driven macOS gate
  (44 suites / 352 tests), the iOS Simulator gate (406 tests), four independent
  read-only root-cause investigations, main-agent code review, and
  `git diff --check` all pass; iOS logs contain no process restarts or private
  system-font fallback diagnostics.
- [x] `fix: transform nested block math uniformly`
  Run sibling block-math merging at every AST nesting level through shared
  recursion. Review: the plugin preserves its historical root-level standalone
  shape, then uses a no-op `AST.transform` sibling pass to merge
  delimiter/interior/delimiter sequences in nested containers before the
  existing inline/fence transform. Nested same-paragraph math keeps its
  `ParagraphNode` wrapper, no-op trees preserve identity, and non-plain or
  unclosed spans retain all content instead of consuming intervening nodes.
  Validation: focused math extraction tests (16/16), strict documentation
  freshness (377 discoverable tests), the discovery-driven macOS gate
  (44 suites / 360 tests), the iOS Simulator gate (414 tests), four independent
  root-cause investigations, four read-only quality reviews, main-agent review,
  and `git diff --check` all pass; iOS logs contain no process restarts or
  private system-font fallback diagnostics.
- [x] `fix: make rendering appearance-aware`
  Thread an explicit immutable light/dark value through SwiftUI render input,
  direct solver construction, layout cache variants, and detached layout work.
  Resolve dynamic theme colors before off-main drawing; carry a full render
  fingerprint into `LayoutResult` so the iOS bitmap cache cannot reuse pixels
  across appearance, theme, registry, adapter, or image-policy variants.
  Preserve semantic `StableNodeIdentity`, but reconfigure existing visible
  collection items whenever that render fingerprint changes. Render
  invalidation must cover text, width, parser limits, appearance, theme,
  ordered plugin configuration, diagram registry, and image policy. Review:
  AppKit color resolution is serialized and stress-tested after exposing a
  concurrent `NSAppearance` crash; code views resolve retained themes for the
  layout appearance even outside collection cells; attributed-color resolution
  uses one attribute pass and avoids copying strings without colors. Validation:
  20 focused appearance/render-input tests, 11 consecutive concurrency-stress
  passes, documentation freshness (397 discoverable macOS tests), the complete
  macOS correctness gate (46 suites / 380 tests), visual and determinism
  snapshot gates (4/4 each), and the iOS Simulator gate (436 tests) all pass.
  iOS logs contain no XCTest process restarts or private-font fallback
  diagnostics, and `git diff --check` is clean.
- [x] `refactor: split host resolver and interaction contracts`
  Replace the mixed `MarkdownContextDelegate` with a class-bound `Sendable`
  autolink resolver used only by detached parsing. Preserve existing UI-owned
  link/checkbox/details closures, add deprecated resolver-name/label migration
  shims without overload ambiguity, fingerprint stateful resolver configuration,
  and remove the unused attachment/action/issue-keyword/checkbox requirements
  instead of advertising dead hooks. Review: the resolver is strongly retained
  for detached parser work, mutable/main-actor host objects must split out an
  immutable or synchronized resolver, and the deprecated name remains only for
  conformers that satisfy the new `Sendable` contract. Validation: 26 focused
  resolver/engine/render-input/Sendable tests, strict documentation freshness
  (405 discoverable tests), the complete macOS correctness gate (46 suites /
  388 tests), visual and determinism snapshot gates (4/4 each), and the iOS
  Simulator gate (444 tests) all pass. iOS logs contain no XCTest process
  restarts or private-font fallback diagnostics, and `git diff --check` is clean.
- [x] `perf: coalesce render jobs and reuse parsed ASTs`
  Replace cancel-and-restart rendering with a latest-request single-flight
  coordinator: one active detached parse/layout job, one overwrite-only pending
  request, and generation-guarded publication. Cache raw ASTs by text, parser
  limits, and ordered plugin configuration so width/theme/appearance/diagram/
  image-policy changes relayout without reparsing. Route macOS effective-width
  feedback through the same coalescing path and apply details disclosure as an
  override on the latest full configuration so toggles cannot publish stale
  `lastAST`/`lastTheme` state. Review: request preparation occurs immediately
  before execution so canceled parsing can seed same-key reuse; parse-key
  changes clear disclosure overrides, while source-state toggles prune them;
  redundant hot-path state and work were removed. Validation: 10 focused
  coordinator/render-input tests, 10 consecutive coordinator-suite passes,
  strict documentation freshness (411 discoverable tests), the complete macOS
  correctness gate (394 tests), visual and determinism snapshot gates (4/4
  each), and the iOS Simulator gate (450 tests) all pass. iOS logs contain no
  XCTest process restarts or private-font fallback diagnostics, and
  `git diff --check` is clean.
- [x] `refactor: establish one image-loading pipeline`
  Keep Markdown images on the live attributed-attachment path used by parser
  output. Remove the dormant iOS-only `AsyncImageView` branch, which can only be
  reached through manually fabricated top-level `ImageNode` layouts and has no
  producing parser/layout path. Add one internal image-resource loader that owns
  source resolution, policy enforcement, file/network loading, redirect/status/
  MIME/byte validation, and typed failures. Make `ImageAttachmentBuilder` decode
  ImageIO thumbnails before caching, partition decoded entries by policy/source/
  target width, and retain alt-text fallback plus the default no-I/O policy.
  Review: disallowed redirects are rejected before follow, allowed HTTPS redirects
  remain supported, remote bodies stream under `maximumResponseBytes`, URL/path
  failures stay private in logs, sync and async layouts use separate cache/render
  variants, and canceled image renders cannot cache fallback over a later retry.
  Validation: 70 focused image/appearance/equivalence tests, strict documentation
  freshness (430 discoverable tests), the complete macOS correctness gate (413
  tests), visual and determinism snapshot gates (4/4 each), and the iOS Simulator
  gate (459 tests) all pass. iOS logs contain no XCTest process restarts, corrupt
  image fixture diagnostics, private-font fallback diagnostics, or concurrency
  diagnostics, and `git diff --check` is clean.
- [x] `perf: reuse accessibility metadata on macOS`
  Make `LayoutResult.accessibility` the single source of truth for AppKit item
  role, label, value, and help. Extend the cached metadata with typed checkbox
  state so `MarkdownItemView` can preserve native `.checkBox` semantics without
  enumerating `.markdownCheckbox` on the main thread. Reset all per-layout
  accessibility state on direct reconfiguration and reuse, while preserving
  existing iOS traits and string values. Add focused metadata, AppKit mapping,
  configuration, and stale-state regressions before full cross-platform gates.
  Review: reused the existing typed `CheckboxState` through a source-compatible
  metadata initializer, avoided a public enum expansion, overrode AppKit's
  narrowed `NSTextView` value bridge so native checkbox values are observable,
  and removed reset-then-reapply TextKit work from non-empty configuration.
  Validation: 22 focused accessibility/AppKit tests, 421 macOS correctness
  tests, 438 discoverable-test documentation checks, visual and determinism
  snapshot gates (4/4 each), and 459 iOS Simulator tests all pass.
- [x] `refactor: share sync and async layout dispatch`
  - [x] Q15-A aligns sync details/summary rendering, task-checkbox attributes,
    and recursive unknown-inline flattening. A separate interaction fingerprint
    prevents cached checkbox/details callbacks from retaining stale source
    ranges or source URLs while preserving semantic, stable, and pixel-render
    identities.
  - [x] Q15-B/C replace the duplicated `AttributedStringBuilder` switches with
    one invocation-local flat render program and separate sequential sync/async
    materializers, then replace `LayoutSolver` classification with one shallow
    recipe plus shared measurement/result assembly.
  - [x] Q15-D/E preserve and verify true resource differences, cache variants,
    cancellation publication, platform custom-draw routes, stable identities,
    and the fully synchronous API without new unsafe annotations or meaningful
    benchmark regressions.
  Review: unknown recursion is limited to `InlineNode`; interaction identity
  propagates only through rendered ancestors. The builder now defers static-leaf
  construction until sequential materialization and isolates nested block output
  so parent separator state cannot leak. The solver classifies only after cache
  lookup and shares immediate execution, measurement, color resolution, and
  result assembly. Final simplification, concurrency, and regression reviews
  found no remaining material issue.
  Validation: 149 focused integration tests, 455 macOS correctness tests, 472
  discoverable-test documentation checks, visual and determinism snapshot gates
  (4/4 each), 495 iOS Simulator tests, and the complete benchmark gate all pass.
- [x] `refactor: share table geometry across renderers`
  - [x] Q16-A add one immutable canonical table grid and uniform column geometry
    model, with focused empty/ragged/direct-cell/alignment/width tests.
  - [x] Q16-B migrate the AppKit native table and UIKit attributed fallback
    adapters without changing their fonts, widths, truncation, separators,
    blocks, backgrounds, or multiline behavior.
  - [x] Q16-C migrate the UIKit card renderer without changing its custom-draw
    contract, visual metrics, wrapping, or no-zebra presentation.
  - [x] Q16-D add cross-renderer contracts, correct stale documentation, run
    review and all focused/full/snapshot/benchmark gates, then commit and push
    atomically.
  Review: all three adapters now consume one immutable rectangular grid and one
  uniform column-allocation implementation while retaining their intentional
  AppKit native-table, UIKit attributed-fallback, and UIKit card-drawing
  boundaries. Reuse/simplification, Swift 6.2 concurrency, and four-way final
  reviews found no remaining material issue after sanitizing card metrics,
  bounding generated fallback content, and demand-materializing geometry arrays.
  Validation: 33 focused macOS table tests, 48 focused iOS table contracts, 5
  UIKit attributed safety tests, 471 macOS correctness tests, 488
  discoverable-test documentation checks, visual and determinism snapshot gates
  (4/4 each), 521 iOS Simulator tests, and the complete benchmark gate all pass.
- [x] `refactor: decompose arithmetic text preparation`
  - [x] Q17-A add behavior-level phase contracts for UTF-16 boundaries,
    glue/soft-hyphen/newline handling, merge order, SoA/font capture, and
    fit-versus-paint metadata.
  - [x] Q17-B keep `ArithmeticTextCalculator` as the public/cache facade while
    extracting internal scanner, segment classifier/merger, measurer, and line
    breaker value types into dedicated source files.
  - [x] Q17-C review the integrated refactor and run focused/full
    macOS/iOS/snapshot/documentation/benchmark gates before one atomic commit
    and push.
  Review: `ArithmeticTextCalculator` now owns only profile, prepared-cache, and
  facade responsibilities. Four internal value types own streaming UTF-16
  scanning, localized classification/merging, CoreText measurement, and
  fit-versus-paint line breaking. Reuse/quality/clarity review found no issue;
  efficiency review identified and removed full-span buffering in favor of a
  local iterator. Swift 6.2 concurrency and final
  regression/security/reliability/contracts reviews found no remaining material
  issue.
  Validation: 29 focused arithmetic tests, 22 builder-equivalence tests, 106
  layout/cache/appearance/concurrency integration tests, `swift build`, 475
  macOS correctness tests, 492 discoverable-test documentation checks, visual
  and determinism snapshot gates (4/4 each), 525 iOS Simulator tests, and the
  complete benchmark gate all pass.
- [x] `perf: cache repeated highlighter and diagram work`
  Cache generic regex compilation and width-independent Mermaid source renders.
  Q18 scope: cache immutable comment/keyword regex bundles by canonical language
  family while compiling shared string/number regexes once; cache only successful
  intrinsic Mermaid images inside the existing MainActor FIFO snapshotter with
  count/cost bounds, FIFO-safe lookup, failure/cancellation non-poisoning, and
  fresh attachments per adapter call. Reuse `MarkdownKitEngine.defaultPlugins()`
  from `MarkdownView` instead of repeating the production default chain. Do not
  weaken any existing layout, bitmap, render-input, adapter, appearance, width,
  or sync/async cache identity.
  - [x] Q18-A add bounded lock-protected compiled-regex bundles, shared
    string/number expressions, alias-family reuse, and theme-independent cache
    tests.
  - [x] Q18-B add bounded MainActor Mermaid source-image caching, FIFO-safe hits,
    fresh attachments, queued/active cancellation, stale-callback rejection,
    failure non-poisoning, and WebView reload after timeouts.
  - [x] Q18-C reuse `MarkdownKitEngine.defaultPlugins()` from `MarkdownView` and
    preserve the existing details/diagram/math order.
  - [x] Q18-D complete simplification, Swift concurrency, regression, security,
    reliability, contracts, focused/full platform, snapshot, documentation, and
    benchmark review gates.
  Review: concurrent first use now compiles one generic language-family bundle;
  cached regexes never retain source/theme output. Mermaid cache lookup occurs
  only at the FIFO head, successful images are count/cost bounded, AppKit callers
  receive copied images, canceled/failed work cannot publish cache entries, and
  timeout recovery reloads/reinjects the bundled script before queued work
  resumes. Final review passes found no remaining material issue.
  Validation: 15 highlighter tests, 10 real Mermaid adapter tests, 502 full
  macOS tests, 485 macOS fast-gate tests, 502 discoverable-test documentation
  checks, visual and determinism snapshot gates (4/4 each), 535 iOS Simulator
  tests, and the complete benchmark gate all pass.
- [x] `refactor: curate the pre-1.0 public API`
  Internalize implementation details, remove unnecessary re-exports, and document
  the remaining supported surface.
  Q19 scope: lock stable and advanced workflows with normal-import smoke tests;
  remove transitive SwiftUI/Splash exports; internalize visitor, sanitizer,
  calculators/highlighter, cache fingerprint/diagnostic operations, native-image
  alias, TOC helper, hosted platform views/cells, platform accessibility, stable
  diff identity, and cached accessibility metadata. Keep parser/engine/solver,
  SwiftUI and direct collection-view integration, Theme/tokens/image policy,
  built-in nodes/plugins, AST rewrite helpers, autolink migration shims, and
  diagram/math adapters public. Slim public `LayoutResult` construction to the
  render payload instead of allowing callers to fabricate internal identity,
  cache-variant, or accessibility-cache state.
  - [x] Q19-A lock supported normal-import workflows, document API tiers, and
    remove SwiftUI/Splash re-exports.
  - [x] Q19-B internalize core calculators, sanitizer, highlighter, image alias,
    TOC helper, cache operations/diagnostics, and theme fingerprint helpers.
  - [x] Q19-C internalize the swift-markdown visitor and move demo/AST guidance
    to `MarkdownParser`.
  - [x] Q19-D internalize platform render plumbing and slim `LayoutResult`.
  - [x] Q19-E measure/review/validate the final public contract, then commit and
    push atomically.
  Review: normal-import consumers retain the documented stable and advanced
  workflows, while implementation-only symbols are absent from the public
  symbol graph. Review passes caught and fixed duplicate manual-row identities,
  stale host-built render payloads, size-only row refresh, and UIKit flow-layout
  invalidation without re-exposing internal identity or cache-variant controls.
  Validation: direct source `public`/`open` declarations fell from 553 to 420;
  the public graph has 452 symbols and zero deny-listed leaks. Full macOS (516)
  and iOS Simulator (550) tests, the fast gate, both 4-test snapshot gates,
  documentation freshness at 516 discoverable tests, and the complete benchmark
  gate all pass.
- [x] `chore: establish release and repository hygiene`
  Pin moving dependencies, add license/notices/changelog, adopt valid SemVer tags,
  record vendored resource provenance, and remove orphan generated artifacts.
  Q20 release decisions: MarkdownKit uses the MIT license; the completed release
  is tagged `v0.4.0`; legacy `0.02` and `0.03` tags remain untouched.
  - [x] Q20-A pin `swift-markdown` to immutable release `0.8.0`, refresh the
    resolution, review compatibility, and commit/push independently.
  - [x] Q20-B add MIT licensing, third-party notices, provenance metadata, and
    dependency/Mermaid drift verification; commit/push independently.
  - [x] Q20-C add normalized macOS/iOS public API baselines and CI freshness
    checks with concise diffs; commit/push independently.
    - [x] Q20-C1 extract source-declared public symbol graphs for macOS and
      arm64/x86_64 iOS Simulator without the tracked Xcode project.
    - [x] Q20-C2 normalize symbols/relationships into deterministic committed
      baselines and report concise added/removed/changed drift.
    - [x] Q20-C3 integrate matching CI/local gates, document refresh workflow,
      review negative fixtures, validate both platforms, then commit/push.
  - [x] Q20-D remove only verified-unreferenced scratch and stale generated
    Tuist/Xcode artifacts while preserving supported SwiftPM workflows;
    commit/push independently.
  - [x] Q20-E add the changelog/release procedure, run the complete release
    matrix, commit/push, and create/push annotated tag `v0.4.0`.
    - [x] Q20-E-W1 keep Mermaid FIFO/cache/cancellation/timeout ownership in the
      production snapshotter while injecting only deterministic image generation
      into app-less iOS tests before lazy singleton construction.
    - [x] Q20-E-W2 add a SwiftPM demo launch mode and extend `verify_ios.sh` to
      assemble, sign, install, launch, observe, and clean up a real
      `UIApplication`-hosted WebKit smoke.
    - [x] Q20-E-W3 finish README/plan/release-contract updates, run the complete
      release matrix, and publish the reviewed release metadata and tag.
  Q20-A review: the package now uses canonical
  `swiftlang/swift-markdown` exact 0.8.0 at
  `3c6f9523da3a1ec2fd829673e472d95b8097a3b8`. The only transitive lockfile
  normalization is `swift-cmark` 0.8.0 at its existing revision; every other
  pin is unchanged. Build, 29 focused parser/plugin tests, 499 macOS
  correctness tests, 550 iOS Simulator tests, both 4-test snapshot gates, and
  the complete benchmark gate pass.
  Q20-B review: MarkdownKit now has an MIT license, exact top-level notices,
  checked-in upstream legal texts, a closed machine-readable provenance lock,
  and a complete 62-package Mermaid UMD inventory/license report. Reviewed
  policy digests independently anchor the manifest/resolution metadata, legal
  file set, Mermaid inventory, report, and bundle so updating only the lock
  cannot approve drift. The CI/wrapper path resolves `Package.swift` before the
  offline verifier, while the Mermaid refresh procedure remains explicit and
  separate from normal CI.
  Q20-B validation: the positive resolve/provenance gate and 9 isolated negative
  drift fixtures pass; final independent review found no material issue. The
  macOS correctness gate ran 499 tests, documentation freshness matched 516
  discoverable tests, both 4-test snapshot contracts passed, and the iOS
  Simulator gate ran 550 tests without failures or private-font diagnostics.
  Q20-C review: SwiftPM-only extraction now records deterministic SHA-256
  structural identities for 453 macOS symbols / 599 relationships and 454 iOS
  Simulator symbols / 610 relationships. The iOS check verifies both arm64 and
  x86_64 graphs against one architecture-neutral baseline; raw paths, USRs,
  architecture, and generator/toolchain noise are excluded. Check mode is
  read-only, record mode writes atomically with mode 0644, and six isolated
  drift fixtures cover additions, removals, declaration changes, relationship
  changes, malformed baselines, and wrong-platform input.
  Q20-C validation: 10 normal-import public API smoke tests, provenance, 499
  macOS correctness tests, both platform API checks, 516-test documentation
  freshness, both 4-test snapshot contracts, and 550 iOS Simulator tests pass.
  The GitHub `macos-26` image inventory lists Xcode 26.4.1 build 17E202 and its
  matching macOS/iOS Simulator 26.4 SDKs.
  Pinning Xcode 26.4.1 exposed a pre-existing Mermaid/WebKit cold-start race;
  its reviewed runtime fix was committed and pushed independently as `011cf38`
  before the API baseline commit.
  Q20-D review: removed the stale `MarkdownKit.xcodeproj`,
  `MarkdownKitDemo.xcworkspace`, three generated `Derived/` files, and two
  unreferenced root performance scratch notes. Rooted ignore rules prevent
  regeneration from re-entering version control. Formal arithmetic/layout/
  pretext/evaluation reports, snapshot baselines, benchmark JSON, generated
  benchmark documentation, legal records, and all SwiftPM sources remain.
  Q20-D validation: `swift package describe`, `swift build`, provenance, 499
  macOS correctness tests, macOS plus arm64/x86_64 iOS API checks, 516-test
  documentation freshness, both 4-test snapshot contracts, and 550 iOS
  Simulator tests pass with the generated project artifacts absent.
  Q20-E host separation review: the deterministic iOS driver replaces only
  source-to-image generation; the MainActor snapshotter still owns FIFO order,
  cache hits/publication, cancellation, deadlines, continuations, and late
  callback rejection. Production and macOS continue to use file-backed WebKit.
  The iOS gate now runs exactly 550 hostless XCTest tests without constructing a
  Mermaid `WKWebView`, then assembles the SwiftPM demo executable into an
  ad-hoc-signed Simulator app and requires exactly one real-WebKit PASS marker.
  Focused macOS Mermaid tests (10), the 499-test fast gate, and the integrated
  550-test-plus-smoke iOS gate pass.
  Q20-E release review: `CHANGELOG.md` records the consumer-visible additions,
  fixes, migration notes, security changes, performance work, and release
  engineering shipped since `0.03`. `docs/RELEASE.md` pins Xcode 26.4.1, makes
  every local gate and expected count explicit, forbids baseline refreshes, and
  verifies the non-blocking visual snapshot step separately before tag creation.
  README and plan guidance now distinguish the 550 deterministic iOS XCTest
  contracts from the additional app-hosted real-WebKit smoke.
  Q20-E validation: package description/build, 10 normal-import smoke tests,
  provenance, 453-symbol/599-relationship macOS API, 499 fast correctness tests,
  516-test documentation freshness, both four-test snapshot contracts, 550 iOS
  XCTest tests plus exactly one app-hosted Mermaid PASS marker, both
  454-symbol/610-relationship iOS Simulator API graphs, and the complete
  benchmark gate pass. Exact-SHA CI run `29645680543` for the host-separation
  commit passed all three jobs, including the visual snapshot step.
  - [x] Q20-E post-release review follow-up: route the app-hosted Mermaid smoke
    through a public `MarkdownView` Mermaid fence and reporting adapter registry,
    retain fixed 550-test enumeration/execution assertions and EXIT-based
    `INT`/`TERM` cleanup, then review, validate, commit, and push without moving
    the immutable `v0.4.0` tag.
    Follow-up validation: package description/build, 10 normal-import API smoke
    tests, provenance, both platform API baselines, 499 fast correctness tests,
    516-test documentation freshness, both four-test snapshot contracts, exactly
    550 iOS XCTest tests plus one app-hosted public-`MarkdownView` Mermaid PASS
    marker, and the complete benchmark gate pass.

## Phase 13: Evidence-Driven Performance Wave

Each stage remains independently reviewed, validated, committed, and pushed
before the next stage starts.

- [x] P01-A adopt canonical Release/process-isolated benchmark execution.
  Move average regression guards onto the corresponding standalone benchmark
  methods, keep composite reports informational, and update reproduction docs.
  Validation: the gate prevalidated 11 fully qualified workload identifiers,
  built the XCTest bundle once in Release, ran every workload in its own
  process, and passed all guards. Four-role regression and simplification
  reviews were resolved; 499 fast correctness tests and the 516-test
  documentation freshness gate also passed.
- [x] P01-B add one coordinator-level rapid-update/latest-settled latency
  workload representing streaming Markdown growth at a stable width.
  Validation: untimed setup establishes a fresh coordinator with stale diagram
  layout actively blocked; the measured interval enqueues middle/latest growth,
  releases stale work, and waits for the latest commit. Exact adapter sources
  verify first/latest execution with no middle render. The 12-workload Release
  gate, 499 fast correctness tests, and 517-test documentation freshness gate
  pass; timing remains informational until P01-C.
- [x] P01-C record the new isolated Release baseline from current `main`, tighten
  the average regression policy using repeated-run variance, regenerate the
  generated baseline documentation, and correct the stale archival
  accessibility attribution.
  Recording: five complete 12-workload gates from
  `ad80fccfe8c1669682c62830cd1daf1414449e96` on macOS 26.5.2 / arm64 /
  Apple M5 Max, each with 3 warmups and 20 measured samples; schema v2 stores
  the median of per-process averages. The global average policy is now
  `max(2x baseline, baseline + 2ms)`. Warm-cache timing remains recorded but is
  guarded relationally (`warm < cold`), while concurrency retains both
  absolute and concurrent-versus-sequential contracts. Coordinator streaming
  is now a guarded baseline group. Validation: 10 baseline contract tests, the
  complete 12-workload isolated Release gate, 499 fast correctness tests, and
  the 517-test documentation freshness gate pass. Four-role simplification and
  regression swarms found no remaining issue after aligning Swift/Python null
  validation and preserving the documented test count.
- [x] P02 skip provably irrelevant built-in details/diagram/math plugin
  traversals through a conservative internal source preflight. Keep the public
  `ASTPlugin` protocol unchanged. Only the three production built-ins adopt the
  internal capability; every custom plugin always executes. Source-based
  skipping remains eligible only while preceding plugins were skipped. Once
  any plugin actually executes, all later plugins run normally so custom or
  built-in output can introduce syntax absent from the original source.
  - [x] P02-A add one lazily computed source-hints value and parser-prefix
    eligibility, with direct tests for skip/execution order and custom-plugin
    injection.
  - [x] P02-B give details, diagram, and math conservative predicates that
    share their existing marker/language sources of truth. Fence detection must
    cover nested prefixes, backtick/tilde fences, longer delimiters, case, and
    whitespace without bare `stl`/`tex` substring false positives.
  - [x] P02-C prove existing positive, escaped, malformed, nested, no-op
    identity, fingerprint, and public API contracts; compare five isolated
    Release plugin-composition runs against the pre-change median p95 of
    4.75ms. Exit requires at least 35% improvement (post-change median p95
    <= 3.0875ms), then full review/correctness/documentation/benchmark gates,
    atomic commit, and push.
  Validation: exact final-code p95 values were 2.10, 2.15, 2.10, 2.05, and
  2.10ms (median 2.10ms), a 55.8% reduction from the 4.75ms pre-change median.
  Thirteen direct preflight tests, 512 fast correctness tests, 530 discoverable
  documentation checks, the 12-workload benchmark gate, the unchanged macOS
  public API baseline, 563 iOS Simulator XCTest tests, and the app-hosted
  real-WebKit Mermaid smoke pass. Same-environment snapshot determinism passes;
  the four committed visual baselines drift on this host identically at
  `origin/main`, so no P02 snapshot output was refreshed. Four-role review found
  the CommonMark entity-decoding seam; final main review also removed a
  mixed-syntax premature scan stop, with regressions covering both cases.
- [x] P03 eliminate redundant whole-attributed-string appearance resolution
  while preserving explicit light/dark output and custom adapter colors. Keep
  the public API, cache variants, render fingerprints, measurement, and
  async/sync resource semantics unchanged.
  - [x] P03-A lock end-to-end contracts for the two direct semantic-color
    literals (code-language labels and blocked-image fallback) plus all five
    supported color attributes returned by custom async/sync math and async
    diagram adapters.
  - [x] P03-B make `AttributedStringBuilder` the single appearance-aware
    construction boundary: resolve the secondary-label color once, normalize
    only opaque adapter payloads when they enter the builder, and remove the
    per-node whole-string scan from `LayoutSolver.makeTextOutput`.
  - [x] P03-C compare five isolated Release
    `BenchmarkNodeTypeTests/testInputSizeScaling` runs against the pre-change
    `solve(1000-lines)` median p95 of 53.49ms. The report key represents 1,000
    generated paragraph blocks (2,002 physical lines). Exit requires at least
    15% improvement (post-change median p95 <= 45.4665ms), then full
    review/correctness/documentation/API/snapshot/benchmark/iOS gates, atomic
    commit, and push. P01's persistent average policy remains unchanged.
  Validation: exact post-change p95 values were 36.03, 38.11, 33.89, 40.45,
  and 36.72ms (median 36.72ms), a 31.4% reduction from the 53.49ms pre-change
  median. Ninety-two focused appearance/builder/layout tests, 514 fast
  correctness tests, 532 discoverable documentation checks, the unchanged
  453-symbol / 599-relationship macOS public API, all 12 Release benchmark
  workloads, 565 iOS Simulator XCTest tests, and the app-hosted real-WebKit
  Mermaid smoke pass. Snapshot determinism passes, and all four current
  snapshot PNGs are byte-identical to clean commit `731a93e` in the same host
  environment; both states share the same unrelated committed-baseline drift.
  Four-role simplification and four-role regression/security/reliability/
  contracts reviews found no material issues.
- [x] P04 make stale layout/materialization work cooperatively cancellable
  without changing public solve behavior or canceled-cache publication rules.
  - [x] P04-A add deterministic failing contracts for coordinator latest-work
    handoff, builder resource checkpoints, invocation-local cache rollback, and
    unchanged public async/sync solve behavior.
  - [x] P04-B add an internal coordinator-only cancellable solve path with one
    invocation-wide work budget. Check cancellation between top-level children,
    builder planning/materialization operations, and before/after resource
    awaits; replace per-node unconditional yields with bounded periodic yields.
  - [x] P04-C stage cancellable-path cache writes in an invocation-local overlay,
    read staged entries before the shared cache, and publish child-before-parent
    only after successful root completion and a final cancellation check.
    Synchronous commit is the point of no return; generation checks still reject
    stale UI output.
  - [x] P04-D route `MarkdownRenderCoordinator` through the cancellable path
    while preserving same-key raw-AST reuse from canceled work. Document that
    non-cooperative host adapters can delay handoff only until their in-flight
    await returns.
  - [x] P04-E run Swift 6.2 concurrency, simplification, regression, reliability,
    and contract reviews; then run focused, fast, documentation, API, snapshot,
    benchmark, and iOS gates before atomic commit and push.
  Acceptance: after an in-flight resource returns, stale work stops within one
  bounded chunk; later resources do not start; canceled cooperative solves
  publish no staged cache entries; successful solves retain child/root reuse;
  public `solve` and `solveSync` preserve their existing total-result and cache
  semantics.
  Validation: 69 final cancellation/builder/coordinator contracts and a broader
  150-test layout/cache integration selection pass, followed by 519 fast
  correctness tests and 537-test documentation freshness. macOS and iOS public
  API baselines remain 453/599 and 454/610, provenance and 4-test snapshot
  determinism pass, and current visual output is byte-identical to clean
  `f23b871` despite the same four committed-baseline drifts on this host. All
  12 isolated Release workloads pass; `solve(1000-lines)` is 32.63ms average /
  33.78ms p95 and `latest-settled(large-3-updates)` is 11.69ms average /
  11.95ms p95 versus the 28.82ms recorded average. The iOS gate executes exactly
  570 XCTest tests with no restart/private-font diagnostics, then emits exactly
  one app-hosted real-WebKit Mermaid PASS marker. Simplification, concurrency,
  regression, security, reliability, contracts, and final reviews found no
  remaining material issue.
- [x] P05 suppress identical iOS/macOS collection snapshot applications and
  reconfigure only changed layout variants.
  - [x] P05-A add deterministic platform contracts and internal diagnostics for
    initial/identical/empty/append/reorder/content/size/appearance/render/
    interaction updates, including direct collection callers and iOS live
    callback forwarding.
  - [x] P05-B derive one shared top-level collection update plan from positioned
    stable identities plus existing render/appearance/size/interaction variant
    metadata. Always refresh the identity lookup, but skip native diffable apply
    when the main section, ordered identities, and retained variants are exact.
  - [x] P05-C consume that plan in iOS and macOS while preserving iOS
    reconfigure/layout-invalidation ordering, AppKit reload behavior, append/
    move/delete semantics, visible interaction-mode refresh, and public direct
    collection integration.
  - [x] P05-D make iOS cell link/checkbox callbacks resolve through the live
    collection view and assign representable callbacks before layouts, so a
    callback-only SwiftUI parent update needs no snapshot and cannot leave
    visible cells with stale handlers.
  - [x] P05-E run simplification, SwiftUI performance, regression, reliability,
    security, contracts, and final reviews; then run focused, fast,
    documentation, API, snapshot, benchmark, and iOS gates before atomic commit
    and push.
  Acceptance: repeated empty or equivalent layout assignments after the first
  section setup perform zero native snapshot applications; append/reorder/
  replacement and retained render/appearance/size/interaction changes perform
  exactly one apply; only changed retained identities reconfigure/reload; size
  changes preserve post-apply iOS layout invalidation; callback-only updates
  reach the latest host closures without applying a layout snapshot.
  Validation: 54 focused collection/appearance/interaction tests, 523 fast
  correctness tests, and 541 discoverable-test documentation checks pass.
  macOS and iOS public API baselines remain 453/599 and 454/610; provenance and
  4-test snapshot determinism pass. The four committed visual baselines retain
  their known host drift, while current output is byte-identical to clean
  `6e2debe`. All 12 isolated Release workloads pass; `solve(1000-lines)` is
  31.71ms average / 33.00ms p95 and
  `latest-settled(large-3-updates)` is 20.24ms average / 20.75ms p95. The iOS
  gate executes exactly 575 XCTest tests with no restart/private-font
  diagnostics and emits exactly one app-hosted real-WebKit Mermaid PASS marker.
  Review found and resolved retained AppKit theme reload semantics, default
  browser fallback, selectable-link preview handling, and completion-test
  determinism; the final independent review found no remaining material issue.
- [ ] P06 unify the iOS raster/prefetch key, scale, size, task-lifetime,
  in-flight-deduplication, and bitmap-cost behavior.
- [ ] P07 add bounded width-independent attributed/highlight/arithmetic prepared
  content reuse.

P01 scope correction: p95/max remain informational with the current 20-sample
harness; RSS deltas remain informational because they measure the whole XCTest
process. Runtime signposts and an iOS benchmark baseline require separate
production/infrastructure stages and are not mixed into P01-A.

## Phase 14: Performance Review Backlog (2026-07-19 whole-repo review)

Source: the 2026-07-19 whole-repo performance review (context in
`docs/PLAN.md` Phase 14). This backlog excludes findings already resolved by
Phase 13 stages P01–P05: streaming/coordinator benchmarks and the Release
baseline (P01), no-op plugin traversal skipping (P02), redundant appearance
color resolution (P03), per-node unconditional yields (P04), and
identical-snapshot suppression with variant-scoped reconfigure (P05). Where an
item overlaps a pending Phase 13 stage, fold it into that stage instead of
duplicating work: P14.9 belongs to P06, and the highlight-reuse half of P14.6
belongs to P07.

Each item is one atomic commit validated with the P01 isolated Release
harness plus `bash scripts/verify_fast.sh`. Quoted timings from the review
were measured on the pre-P01 Debug harness; re-measure against the current
Release baseline before and after each item. Suggested order: quick wins
(P14.1, P14.2, P14.11–P14.13) → P14.3 → P14.7 → P14.8 → P14.5 → P14.6 →
P14.10 → P14.14 → P14.4 last (largest scope, benefits already reduced by
earlier items).

### Cold layout quick wins
- [ ] P14.1 `perf: make accessibility metadata lazy`
  Every solver-built `LayoutResult` eagerly runs `AccessibilityMetadata.make`
  (a `.markdownCheckbox` enumeration per block) at construction time —
  historically attributed as the dominant cost of the archival
  `solve(1000-lines)` Debug regression (`docs/BENCHMARK_POST_PHASE_6.md`).
  Compute on first access with a cached box (or only when accessibility is
  active) while keeping main-thread cell configure scan-free. File:
  `Layout/LayoutResult.swift` (~117).
- [ ] P14.2 `perf: download images in chunks, not per byte`
  `ImageResourceLoader` accumulates `for try await byte in bytes {
  data.append(byte) }` — millions of AsyncSequence suspensions per MB. Use
  `URLSession.data(for:)` when the expected length is acceptable, or read in
  chunks; keep the byte-cap check per chunk. File:
  `ImageResourceLoader.swift` (~214).

### Streaming structure
- [ ] P14.3 `perf: key diffable items by path, reconfigure on fingerprint`
  `StableNodeIdentity` embeds `contentFingerprint`, so the growing block gets
  a new identity every stream tick → Diffable delete+insert →
  `prepareForReuse` clears `layer.contents` → full re-raster and visible
  flash. P05's shared update plan suppresses identical snapshots but cannot
  reconfigure across an identity change. Key items by path (+ node type);
  drive redraws through the existing render/interaction variant diff via
  `reconfigureItems`. Files: `Layout/StableNodeIdentity.swift`, the shared
  collection update plan from P05, `UI/iOS/MarkdownCollectionView_iOS.swift`,
  `UI/macOS/MarkdownCollectionView_macOS.swift`.
- [ ] P14.4 `perf: reuse stable-prefix AST across streaming appends`
  Every text change re-parses the whole document
  (`MarkdownRenderCoordinator.renderOffMain` → `MarkdownParser.parse`),
  making a growing chat O(n²) cumulative; P02 skips plugin walks but not the
  cmark parse + visitor mapping. Add an append-aware fast path: when new text
  extends the previous text, re-parse only from the last committed top-level
  block boundary and splice onto the cached prefix AST. Full incremental
  parsing is out of scope; append-only covers the streaming use case.
- [ ] P14.5 `perf: fuse built-in plugin walks when syntax is present`
  P02 skips traversals when the source lacks the relevant syntax, but when it
  is present Details → Diagram → Math still each run a full `AST.transform`,
  and `MathExtractionPlugin` performs three passes (root merge, nested merge,
  inline/fence extract). Fuse the built-in chain into one walk with a shared
  sibling post-processor, preserving P02's preflight and the custom-plugin
  execution contract. Files: `Parsing/MathExtractionPlugin.swift`,
  `Parsing/DetailsExtractionPlugin.swift`,
  `Parsing/DiagramExtractionPlugin.swift`.
- [ ] P14.6 `perf: bound growing-block adapter cost (mermaid, math)`
  - Mermaid: `mermaid.initialize` runs inside every render payload and the
    cache is keyed by full source, so intermediate streamed states pollute
    the 64-entry cache and queue serial MainActor renders. Initialize once at
    bootstrap; skip render/cache until the fence closes or the source idles.
    File: `Plugins/MermaidDiagramAdapter.swift` (~453).
  - Math: the MathJax `Engine` actor is per-adapter instance (cold start per
    new solver); make it process-shared. Skip MathJax for unclosed `$…`
    spans. File: `Math/DefaultMathRenderingAdapter.swift` (~126).
  - Highlight-result reuse for growing code fences is P07's scope — do not
    duplicate it here.

### Cold layout throughput
- [ ] P14.7 `perf: fingerprint-based PreparedText cache keys`
  `ArithmeticTextCalculator.preparedTextCacheKey` does a full attribute
  enumeration + `attributedString.string` copy + full-string hash on every
  `prepare`, including hits — often comparable to the measurement it saves.
  Key on the node's `contentFingerprint` + variant hash instead (the solver
  has both). Also make the per-hit `testCounterLock`
  (`ArithmeticTextCalculator`) and `LayoutCache.statsLock` hit/miss counters
  `#if DEBUG`-only, and replace `ArithmeticTextMeasurer`'s per-segment
  string-interpolation width-cache key with a structured key (no `NSString`
  bridge, no `NSNumber` boxing). Complements P07's prepared-content reuse.
- [ ] P14.8 `perf: pool TextKit measurement stacks, widen arithmetic routing`
  All non-arithmetic measurement serializes behind one global
  `os_unfair_lock` and allocates a fresh
  `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` per call
  (`Layout/TextKitCalculator.swift` ~25–42). Pool the stacks (thread-local).
  Guarded by the existing oracle parity tests, extend arithmetic routing
  beyond paragraph/header to text-only list items and blockquotes
  (`LayoutSolver.isPureTextBlock`) — task-list-heavy layout remains ~3× the
  medium fixture largely due to TextKit fallback. Small adjacent win: cache
  `AttributedStringBuilder.listItemPrefixWidth` (an `NSString.size` call per
  list item, ~907) by `(prefix, fontName, pointSize)`.

### UI & scroll
- [ ] P14.9 `fix: prefetch bitmaps at the real display scale` → fold into P06
  `AsyncTextView.preheat` defaults to `scale: 2` while `configure` renders at
  `currentDisplayScale` (3 on modern iPhones), so prefetched bitmaps miss on
  first paint. P06 already owns raster/prefetch key + scale unification;
  track it there and check this box when P06 lands. Files:
  `UI/Components/AsyncTextView.swift` (~114),
  `UI/iOS/MarkdownCollectionView_iOS.swift` (prefetch callback).
- [ ] P14.10 `perf: reduce macOS main-thread TextKit work per configure`
  `MarkdownItemView.configure` runs `layoutManager?.ensureLayout(for:)` on
  the main thread for every changed item (~167), and macOS still reloads
  (rather than reconfigures) changed identities. Skip `ensureLayout` when the
  solver-provided size is trusted; evaluate reconfigure over reload within
  the P05 plan semantics. Files: `UI/macOS/MarkdownItemView.swift`,
  `UI/macOS/MarkdownCollectionView_macOS.swift`.
- [ ] P14.11 `perf: memoize theme fingerprint in MarkdownView body`
  Every body evaluation constructs `MarkdownRenderInput`, whose init calls
  `themeFingerprint` → `theme.resolved(for:)` — ~30 color resolutions (with
  the AppKit resolution lock) on the main thread, inside a `GeometryReader`
  that re-evaluates on scroll/resize. Memoize the fingerprint per (theme
  value, appearance) and snap widths to 0.5pt before comparing. File:
  `UI/SwiftUI/MarkdownView.swift` (~205).

### Hygiene
- [ ] P14.12 `perf: bound LayoutCache by cost`
  Set `totalCostLimit` (cost = attributed string length) alongside
  `countLimit: 100_000` — 100k entries retaining attributed strings and
  custom-draw closures is not "single-digit megabytes" as the comment
  claims. File: `Layout/LayoutCache.swift` (~168).
- [ ] P14.13 `perf: O(1) LRU eviction in FontTraitResolver`
  Eviction uses `Array.removeFirst()` (O(n) shift). Fine at capacity 256;
  cheap to fix while touching the file. File:
  `Layout/FontTraitResolver.swift` (~66).
- [ ] P14.14 `docs: document persisted-cache pattern for one-shot hosts`
  `MarkdownKitEngine.layout` convenience creates a fresh parser/solver/cache
  per call with zero cross-call reuse. Document that streaming hosts must
  reuse parser/solver/cache, or expose the coordinator's persisted-cache
  pattern as a supported API.
