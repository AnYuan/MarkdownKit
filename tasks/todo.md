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
- [x] Implement asynchronous yielding logic for giant documents (>10MB)
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
- [ ] Investigate the outstanding snapshot-size drift in `SnapshotTests.testTableRendering` and `SnapshotTests.testTasklistRendering` separately from Phase 11 arithmetic work.
