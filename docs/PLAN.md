# Implementation Plan: High-Performance Markdown Renderer

## Executive Summary
This document breaks down the execution strategy to fulfill the requirements defined in the PRD. The objective is to build a high-performance, ChatGPT-aligned Markdown renderer for iOS 17.0+ and macOS 26.0+ via Swift 6.0+. The architecture emphasizes background layout calculation, extensive syntactical support (including LaTeX math), and an extensible AST middleware.

## Related Docs
- Technical debt roadmap: `docs/TechnicalDebtRoadmap.md`
- Rendering sequence diagram: `docs/RenderingPipelineSequence.md`

## Current Execution Plan: Automation-First Verification Program
This execution wave prioritizes automated verification before adding more feature surface. The goal is to remove manual UI checking as the default validation path.

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
1. Add explicit regression tests for details toggle state handling.
2. Add explicit regression tests for table readability (no column collapse, alignment correctness).
3. Add explicit regression tests for image attachment rendering and fallback behavior.
4. Add explicit regression tests for diagram fallback rendering behavior.

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
3. Add benchmark regression assertions with versioned baseline thresholds:
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
6. Keep deep/full benchmark report feature-complete (no scenario drop between ad-hoc and full-report tests).

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
**Goal**: Design the layout calculation engine that operates off the main thread to guarantee O(1) rendering time relative to file size.
1. Define `LayoutResult` models containing exact core graphics `{x, y, width, height}` coordinate geometries and drawing contexts.
2. Build the Layout Engine using `TextKit 2` bounding-box solvers running entirely inside a GCD background queue.
3. Implement a chunking and yielding mechanism to ensure parsing and sizing massive documents do not spike memory unpredictably.
4. **Quality Assurance**: Develop unit tests verifying mathematically perfect framing calculations for varying device screen widths and dynamic type sizes.

## Phase 3: Virtualized Rendering UI
**Goal**: Only instantiate UI layers when components enter the viewport, and completely eliminate main-thread blocking during rendering.
1. **iOS**: Implement a high-performance `UICollectionView` handling virtualization.
2. **macOS**: Implement the `NSTableView`/`NSCollectionView` AppKit equivalents.
3. Develop individual native View components for each layout node (e.g., `MarkdownTextView`, `MarkdownImageView`, `MarkdownCodeView`).
4. **Texture Display State**: Specifically mandate that all text rendering (drawing `NSAttributedString` to a `CGContext`) and all `Image/GIF` data decoding must occur strictly on a background queue.
5. Implement the asynchronous mounting logic—applying the pre-drawn contexts to views dynamically as the user scrolls.
6. **Quality Assurance**: Perform memory profiling confirming the footprint remains under 100MB even for millions of words.

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
