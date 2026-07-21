# Implementation Plan: High-Performance Markdown Renderer

## Executive Summary
This document breaks down the execution strategy to fulfill the requirements defined in the PRD. The objective is to build a high-performance, ChatGPT-aligned Markdown renderer for iOS 17.0+ and macOS 26.0+ via Swift 6.0+. The architecture emphasizes background layout calculation, extensive syntactical support (including LaTeX math), and an extensible AST middleware.

## Related Docs
- Technical debt roadmap: `docs/TechnicalDebtRoadmap.md`
- Rendering sequence diagram: `docs/RenderingPipelineSequence.md`
- Concurrency contract: `docs/ConcurrencyContract.md`
- Codebase knowledge snapshot: `docs/CodebaseKnowledge.md`
- Next atomic checklist: `docs/ImplementationChecklist.md`

## Current Execution Plan: Automation-First Verification Program
This execution wave prioritizes automated verification before adding more feature surface. The goal is to remove manual UI checking as the default validation path.

### Verification Entry Point (2026-03-04)
Primary daily gate is now explicitly split:

Fast regression gate:

```bash
bash scripts/verify_fast.sh
```

Heavy benchmark gate:

```bash
bash scripts/verify_benchmarks.sh
```

Combined wrapper:

```bash
bash scripts/verify_all.sh
```

The combined wrapper always runs fast suites first, then optionally runs benchmark suites with `--with-benchmarks`.

For release-level validation, follow the [release procedure](RELEASE.md). Its full matrix includes
package/build checks, macOS and iOS public API checks, provenance, fast and iOS correctness,
documentation freshness, visual and determinism snapshots, and benchmarks; `verify_all.sh --full`
alone is not release validation.

The iOS release gate is deliberately two-part: 647 app-less XCTest tests exercise Mermaid's
queue/cache/cancellation state machine through a deterministic image driver, then a separately
assembled SwiftUI Simulator app proves that a Mermaid fence can traverse public `MarkdownView`
and its registry-backed real-WebKit adapter.

### Phase A: Test Strategy Baseline (Docs + Scope Lock)
**Goal**: lock verification scope and merge criteria.
1. Update PRD quality sections with mandatory automation gates.
2. Define coverage matrix for all supported syntax families.
3. Define deterministic CI constraints (no network dependency by default).

### Phase B: Syntax Matrix Harness
**Goal**: one command validates all supported syntax across width variants.
1. Add a table-driven syntax matrix test suite.
2. Validate parser output with active plugin chain (details + diagrams + math).
3. Run layout passes at narrow, medium, and wide widths.
4. Assert baseline invariants: non-empty output, finite geometry, stable child counts.

**Status (2026-02-27)**: In progress
- [x] Table-driven syntax matrix suite added (`SyntaxMatrixTests`)
- [x] Active plugin chain validation added (details + diagrams + math)
- [x] Width matrix assertions added (narrow/medium/wide)
- [x] Baseline layout invariants added (non-empty output, finite geometry, stable child counts)

### Phase C: Targeted Regression Pack
**Goal**: prevent recurrence of known rendering failures.
1. ✅ Add explicit regression tests for details toggle stale-configuration handling (`MarkdownRenderCoordinatorTests.testDebouncedDarkToggleUsesLatestConfigurationWithoutReparse`).
2. Add explicit regression tests for table readability (no column collapse, alignment correctness).
3. ✅ Add explicit regression tests for the unified inline image path: policy/source/response validation in `ImageResourceLoaderTests`, bounded decode/cache behavior in `ImageAttachmentBuilderTests`, and bracketed alt fallback in layout tests. Remote cases use injected `URLProtocol` responses rather than the public network.
4. Add explicit regression tests for diagram fallback rendering behavior.

Phase C note: this coordinator/details regression fix does **not** claim the separate iOS details tap-gesture gap is fixed.

### Phase D: Stress and Mixed-Case Reliability
**Goal**: catch crashers and pathological layout behavior.
1. Add deterministic mixed-syntax permutation tests.
2. Validate no crash and no invalid size output across multiple widths.
3. Track runtime and optimize slow paths where needed.

### Phase E: Optional Visual Baselines
**Goal**: guard high-value visual styles.
1. Add snapshot coverage for tables, code blocks, inline code, details, and math where feasible.
2. Keep snapshots versioned and reviewable in PRs.

### Phase F: Benchmark Hardening & Regression Gates
**Goal**: make benchmark suites complete, comparable, and CI-enforceable.
1. Add missing benchmark fixtures for plugin-hit scenarios:
   - `details-heavy`
   - `diagram-heavy`
   - `tasklist-heavy`
   - math-focused tier fixtures
2. Extend per-node-type and tiered benchmarks to include plugin-backed syntax families:
   - details
   - diagrams
   - task lists
   - math
3. Add benchmark regression assertions with versioned baseline thresholds and the relational prepared-content guard:
   - compare measured metrics against baseline budget
   - fail test on significant regression
   - keep baseline update path explicit
4. Split cache benchmarks into clear modes:
   - cold-per-iteration
   - warm-hit-only
   - eviction-thrash
5. Normalize concurrency benchmark methodology:
   - align sequential vs concurrent measurement scope
   - include 1/2/4/8 worker scaling in full-report path
6. Keep deep/full benchmark report feature-complete (no scenario drop between ad-hoc and full-report tests) across the 13 canonical isolated Release workloads.

**Status (2026-02-27)**: In progress
- [x] F1. Add missing fixtures and wire them into benchmark suites
- [x] F2. Add baseline guard assertions for benchmark regression gating
- [x] F3. Refactor cache benchmarks to isolate cold/warm/eviction paths
- [x] F4. Refactor concurrency benchmarks for apples-to-apples comparisons
- [x] F5. Refresh benchmark baseline docs after rerun

**Task Breakdown (Execution Order)**
1. Add fixture/model changes (`BenchmarkFixtures`, `BenchmarkTieredFixtures`).
2. Expand benchmark coverage (`MarkdownKitBenchmarkTests`, `BenchmarkNodeTypeTests`).
3. Introduce regression guard utility + threshold table in tests.
4. Update cache/concurrency benchmark implementations and labels.
5. Run focused benchmark tests, tune thresholds, then update baseline docs.

### Delivery Order (Implement One by One)
1. Phase B (Syntax matrix harness)
2. Phase C (Known regression pack)
3. Phase D (Stress reliability)
4. Phase E (Visual baselines)
5. Phase F (Benchmark hardening & regression gates)

## Phase 1: Core Parsing Engine
**Goal**: Integrate `swift-markdown` and construct our proprietary, thread-safe Abstract Syntax Tree (AST) models.
1. Initialize the Swift Package inside the `MarkdownKit` workspace and import Apple's `swift-markdown`.
2. Create internal AST node structures (e.g., `DocumentNode`, `ParagraphNode`, `ImageNode`, `CodeBlockNode`, `MathNode`).
3. Implement a `MarkupVisitor` to parse the `cmark-gfm` output strictly into our internal thread-safe models.
4. Establish the AST Middleware/Plugin system allowing arbitrary manipulation of nodes before moving to the rendering phase.
5. **Quality Assurance**: Write 100% test coverage unit tests proving parsing fidelity against both CommonMark and GitHub Flavored Markdown (GFM) specs.

## Phase 2: Asynchronous Layout Engine (Texture-Inspired)
**Goal**: Design the layout calculation engine that operates off the main thread, targeting per-cell sizing cost that stays independent of total document size. (This has not yet been formally benchmarked or guaranteed as O(1).)
1. Define `LayoutResult` models containing exact core graphics `{x, y, width, height}` coordinate geometries and drawing contexts.
2. Build the Layout Engine using `TextKit 2` bounding-box solvers running entirely inside a GCD background queue.
3. (Deferred) Implement a chunking/yielding mechanism so parsing and sizing very large documents don't spike memory unpredictably. Today, `MarkdownParser` instead enforces a conservative default input ceiling (`ResourceLimits.maximumInputBytes` = 1 MiB) and reports oversized input via `parseOutcome(_:)` rather than streaming or chunking it.
4. **Quality Assurance**: Develop unit tests verifying mathematically perfect framing calculations for varying device screen widths and dynamic type sizes.

## Phase 3: Virtualized Rendering UI
**Goal**: Only instantiate top-level UI layers when components enter the viewport, keeping backing-store rendering off the main thread.
1. **iOS**: Implement a high-performance `UICollectionView` handling virtualization.
2. **macOS**: Implement the `NSTableView`/`NSCollectionView` AppKit equivalents.
3. Develop native text and code view components for top-level layout rows.
4. **Texture Display State**: Draw `NSAttributedString` content—including inline image attachments—into a `CGContext` off-main, then mount the backing store from UI context.
5. Build inline image attachments during layout through `ImageResourceLoader` and `ImageAttachmentBuilder`; image policy changes relayout rather than reconfigure visible cells. No top-level/block-image route is implemented.
6. **Quality Assurance**: (Deferred) Perform memory profiling to characterize footprint under large-document workloads; no fixed ceiling has been measured or is guaranteed yet.

## Phase 4: Extended Syntax & Rich Elements
**Goal**: Perfect alignment with the ChatGPT App feature sets.
1. **Rich Code Blocks**: Integrate a high-speed syntax highlighter (like Splash or similar native tool). Attach a native "Copy Code" button and language indicator overhead.
2. **Complex Math & Equations**: Integrate robust LaTeX bridging (e.g., KaTeX/MathJax via lightweight WKWebView injection, or native equation parsers like iosMath/SwiftMath if capable of complex macros).
3. **Theming Engine**: Build the unified Typography and Color token system supporting Day/Night mode automatically.
4. **Quality Assurance**: Write extensive automated UI Layout tests ensuring LaTeX blocks and highlighted code size properly without horizontal truncation.

## Phase 5: Delivery & Refinement
**Goal**: Finalize stability and code hygiene.
1. Thoroughly execute the Self-Improvement Loop defined in `GEMINI.md`.
2. Clean up memory leaks or performance hitches found during rigorous stress testing.
3. **Quality Assurance**: Snapshot tests for the final render output ensuring complete visual parity with the expected ChatGPT-app visual designs. 

## Phase 11: High-Performance Pure Arithmetic Layout Engine (Pretext-inspired)
**Goal**: Bypass TextKit overhead and locks for pure text nodes using Structure of Arrays (SoA) and direct CoreText width measurements.
*Execution Strategy: strictly atomic commits. The detailed commit-by-commit checklist now lives in `tasks/todo.md` and remains the execution source of truth for this phase.*
1. Arithmetic text layout now has explicit `prepare(...)` and `layout(...)` phases, plus prepared-paragraph reuse for width relayout.
2. Segment semantics now cover glue, zero-width breaks, soft hyphen, hard breaks, grapheme fallback, locale-aware tokenization, URL merges, numeric chains, and basic CJK sticky boundaries.
3. `LayoutSolver` gates arithmetic routing through a prepared-text profile so unsupported scripts and attachment-heavy content continue to use `TextKitCalculator`.
4. Oracle coverage now exists for both arithmetic-parity text cases and complex-script fallback cases against `TextKitCalculator`.
5. The refreshed arithmetic benchmark snapshot is published in `docs/BENCHMARK_BASELINE.md`, and the macOS table/task-list snapshot suite is back to green after the follow-up spacing fix and reference refresh.

## Phase 14: Performance Review Backlog (post-v0.4.0 whole-repo review, 2026-07-19)
**Goal**: Track the remaining findings from the 2026-07-19 whole-repo performance review that are not already covered by the Phase 13 Evidence-Driven Performance Wave (`tasks/todo.md`).
*Execution Strategy: strictly atomic commits, one finding per commit, each validated with the Phase 13 isolated Release benchmark harness (P01) plus `verify_fast.sh`. The detailed trackable checklist lives in `tasks/todo.md` ("Phase 14") and is the execution source of truth for this phase.*

### Review Context
The review predated the Evidence-Driven Performance Wave; several of its findings have since landed on `main` and are excluded here:
- Streaming/coordinator benchmarks and a Release-isolated baseline → P01-B/C.
- No-op built-in plugin traversals skipped via conservative source preflight → P02.
- Redundant whole-attributed-string appearance color resolution → P03.
- Per-node unconditional `Task.yield()` replaced with bounded periodic yields on a cancellable path → P04.
- Identical collection snapshot suppression and variant-scoped reconfigure → P05.
- Hard-coded @2x raster prefetch → P06.
- Unchanged-content width relayout/highlight/arithmetic reuse → P07.

The remaining findings fall into four groups:
1. **Streaming structure**: the growing block still changes `StableNodeIdentity` every tick (Diffable delete+insert instead of reconfigure); the whole document is still re-parsed on every text change; when the relevant syntax *is* present, Details/Diagram/Math still walk the AST separately (Math three times); Mermaid re-runs `mermaid.initialize` per render and caches intermediate streamed sources; the MathJax engine is cold per solver instance.
2. **Cold layout taxes**: eager `AccessibilityMetadata.make` per `LayoutResult`; PreparedText cache keys that copy and hash the full string on every lookup plus always-on stats locks; one global TextKit lock with per-call stack allocation, and arithmetic routing limited to paragraph/header. P14.7 keeps the residual direct PreparedText key/stats/structured-measurer-key cleanup pending.
3. **UI**: a per-byte async image download loop; macOS main-thread `ensureLayout` per item configure; per-body-evaluation theme fingerprint resolution in `MarkdownView`.
4. **Hygiene**: `LayoutCache` lacks a `totalCostLimit`; O(n) LRU eviction in `FontTraitResolver`; the cache-reuse requirement for one-shot `MarkdownKitEngine.layout` hosts is undocumented.
