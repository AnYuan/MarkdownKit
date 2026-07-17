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
- [ ] `fix: reject numeric commit-autolink false positives`
  Preserve issue references while leaving ordinary long numeric identifiers as text.
- [ ] `fix: transform nested block math uniformly`
  Run sibling block-math merging at every AST nesting level through shared recursion.
- [ ] `fix: make rendering appearance-aware`
  Thread appearance through render input, layout environment, and cache identity.
- [ ] `refactor: split host resolver and interaction contracts`
  Separate background `Sendable` autolink resolution from main-actor UI callbacks.
- [ ] `perf: coalesce render jobs and reuse parsed ASTs`
  Bound in-flight parsing and skip reparsing for width-only layout changes.
- [ ] `refactor: establish one image-loading pipeline`
  Decide the supported image surfaces, centralize fetch validation, and downsample
  live inline images before caching.
- [ ] `perf: reuse accessibility metadata on macOS`
  Remove repeated main-thread attributed-string scans during item configuration.
- [ ] `refactor: share sync and async layout dispatch`
  Eliminate duplicated node dispatch while preserving synchronous and asynchronous APIs.
- [ ] `refactor: share table geometry across renderers`
  Keep platform renderers thin over one normalization and sizing model.
- [ ] `refactor: decompose arithmetic text preparation`
  Separate scanning, segment classification/merging, measurement, and line breaking.
- [ ] `perf: cache repeated highlighter and diagram work`
  Cache generic regex compilation and width-independent Mermaid source renders.
- [ ] `refactor: curate the pre-1.0 public API`
  Internalize implementation details, remove unnecessary re-exports, and document
  the remaining supported surface.
- [ ] `chore: establish release and repository hygiene`
  Pin moving dependencies, add license/notices/changelog, adopt valid SemVer tags,
  record vendored resource provenance, and remove orphan generated artifacts.
