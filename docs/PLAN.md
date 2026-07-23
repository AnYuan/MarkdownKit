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

The iOS release gate is deliberately two-part: 725 app-less XCTest tests exercise Mermaid's
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
6. Prepared arithmetic content now models paragraph boundaries explicitly with per-paragraph chunk ranges, first/subsequent-line indents, spacing, and empty-line height while preserving CRLF, U+2028/U+2029, separator-font, soft-hyphen, oversized-token, and used-rect behavior.

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
- Lazy accessibility metadata → P14.1 closed without code: corrected profiling
  measured it at about 0.9%, and laziness would move mounted-row scans to main.
- Per-byte async image response accumulation → P14.2 now uses a reusable
  delegate transport with early validation and bounded `Data` chunks.
- Per-body theme fingerprint resolution → P14.11 now uses a per-engine,
  current-theme light/dark memoizer and carries the selected value through
  solver keying.

P14.2 improved the isolated 4 MiB injected-response median from 75.65ms to
0.245ms (99.7%) while preserving redirect, response-validation, byte-cap, and
cancellation contracts. Twenty-one focused loader tests, 596 fast tests, 615
discoverable tests, 656 iOS tests, both platform API baselines, snapshots,
provenance, and all 13 canonical Release workloads pass.

P14.11 reduced the isolated 2,048-call render-input factory median from 41.10ms
to 3.09ms (92.5%) while preserving theme/appearance invalidation, raw width
semantics, and solver configuration. Six focused coordinator contracts cover
memoizer hits, appearance slots, theme replacement, and render submission.

P14.12 added a 64 MiB advisory `LayoutCache.totalCostLimit` while keeping the
100,000-entry limit, cache key identity, write-batch cancellation/commit
behavior, public `init(countLimit:)`, and public API unchanged. `LayoutResult`
now precomputes a saturating retained-cost estimate from a fixed entry charge,
attributed UTF-16 length, direct child/subtree estimates, and conservative
custom-draw size cost, and entries larger than a positive configured limit are
deterministically not retained. The temporary benchmark was removed after the
isolated pre median average moved from 3.52ms to 3.67ms (+4.3%), still within
the 4.05ms threshold; 27 focused tests pass, including immutable attributed
payload/cost preservation after source mutation.

P14.13 replaces `FontTraitResolver`'s insertion-order array and O(n)
`removeFirst()` shift with a strict 256-entry dictionary-backed LRU whose hit
promotion and tail eviction are O(1). Exact descriptor keys, derive-outside-lock
double checking, cached `Font` identity, hit/miss accounting, and platform font
output remain unchanged. Four direct cache contracts cover eviction order, hit
promotion, object identity/no repeat derivation, and non-positive test
capacities. Final validation passes 31 focused tests, 618 fast tests, 637
discoverable tests, unchanged macOS/iOS APIs, both snapshot contracts, 678 iOS
tests plus the app-hosted WebKit smoke, and all 13 isolated Release workloads.

P14.3 replaces content-derived positioned diffable identity with exact top-level
index plus exact dynamic `MarkdownNode` type. Unpositioned/cache results remain
type-and-content-discriminated, same-type content growth is detected through the
existing render/appearance/size/interaction variant diff, and concrete type
replacement remains structural. Review also closed retained-cell lifecycle gaps:
empty output clears stale rasters, link/checkbox interaction is disabled until
the matching replacement raster mounts, code copy stays aligned with the visible
generation, and optional iOS accessibility metadata is overwritten with `nil`.
Final validation passes 109 focused macOS tests, 65 focused iOS tests, 623 fast
tests, 642 discoverable tests, unchanged macOS/iOS public APIs, both snapshot
contracts, 686 iOS tests plus the app-hosted WebKit smoke, and all 13 isolated
Release workloads. Final whole-diff review found no material issue.

P14.7 tested, then rejected, a proposed second fingerprint-keyed `PreparedText`
namespace: the exact all-miss Release workload improved only 2.7%, below its
frozen 10% gate, while duplicating P07's identity and retained payload. The
merged scope instead removes test-only calculator/LayoutCache diagnostics from
Release hot paths and replaces interpolated `NSString`/boxed `NSNumber` segment
width caching with an exact-UTF-8 typed key, direct `CGFloat` values, a lazy
strict 50,000-entry FIFO, and UIKit/AppKit pressure purging. Five-process
medians improved 12.2% for 10,000 prepared-cache hits and 6.1% for 2,560
width-cache preparations. Debug and Release diagnostic contracts share one test
helper; the temporary benchmarks are not part of the permanent 13-workload
matrix. Final validation passes package describe/build, 10 public API smokes,
provenance, 639 fast tests / 658 discoverable tests, unchanged macOS/iOS API
graphs, both four-test snapshot contracts, exactly 703 iOS tests plus the
app-hosted WebKit smoke, and all 13 isolated Release workloads. Four final
read-only review roles found no material issue.

P14.8 tested reusable TextKit 1 state and shipped no production change. The
exact `2374d7c` baseline measured 13.90ms median for 1,000 short measurements
and 43.78ms for 256 paragraph measurements, with frozen 20% and 10%
improvement gates. A fully reusable stack with post-call clearing regressed the
medians to 17.63ms and 51.65ms. The best narrower design retained only the
layout manager/container and attached fresh storage per call; it reached
12.98ms (6.6% faster, below threshold) and 47.78ms (9.1% slower). Allocation
deltas fell, but TextKit mutation/detachment cost outweighed one-shot stack
construction. Review corrected a non-independent experimental oracle, then all
source, test, and temporary benchmark changes were removed.

P14.15 makes arithmetic prepared content paragraph-aware: each paragraph owns
its chunk range, first/subsequent-line indents, spacing, and empty-line height,
while CRLF, U+2028/U+2029, separator-font, trailing-space, soft-hyphen,
oversized-token, and finite used-rect behavior remain aligned with TextKit.
Review found and fixed both an AppKit default-line-height cache collision and a
prepared-cache collision between font sizes with distinct line heights; exact
font-size and paragraph-metric identities now preserve those payloads. A
single-paragraph streaming path, leading-attribute reuse, and cache-miss-only
CoreText scratch allocation keep the richer model within its frozen budget.
Five final isolated Release processes produced median avg/p95 values of
56.56/58.68ms cold-first, 33.11/33.99ms width-sweep, and 130.9/137.9ms
rebuild-sweep. Final validation passes 92 focused tests, 661 fast tests, 680
discoverable tests, unchanged macOS/iOS public APIs, both snapshot contracts,
725 iOS tests plus the app-hosted WebKit smoke, and all 13 isolated Release
workloads. Final review found no remaining material issue.

The remaining findings fall into four groups:
1. **Streaming structure**: the whole document is still re-parsed on every text change; when the relevant syntax *is* present, Details/Diagram/Math still walk the AST separately (Math three times); Mermaid re-runs `mermaid.initialize` per render and caches intermediate streamed sources; the MathJax engine is cold per solver instance.
2. **Cold layout taxes**: Direct `ArithmeticTextCalculator` callers still build
   the complete attributed-run cache key, but the attempted solver fingerprint
   namespace was not worth its duplicate cache complexity. The larger remaining
   costs are one global TextKit lock with fresh per-call stack construction
   (P14.8 disproved the tested reuse designs), wider list/blockquote arithmetic
   routing that remains deliberately deferred to P14.17 pending builder-backed
   oracle and benefit evidence, and repeated cold list-prefix measurement.
3. **UI**: macOS main-thread `ensureLayout` per item configure.
4. **Hygiene**: the cache-reuse requirement for one-shot
   `MarkdownKitEngine.layout` hosts is undocumented.
