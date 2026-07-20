# MarkdownKit Codebase Knowledge (2026-07-18)

This document is a practical snapshot of the current repository, with emphasis on commands, architecture, and known risks that are still actionable.

## 1. Repository Snapshot

- Branch at snapshot: `main`
- Release: `v0.4.0`
- Swift tools: `6.2`
- Platforms: `iOS 17+`, `macOS 26.0+`
- Dependencies:
  - `swiftlang/swift-markdown` (exact `0.8.0`)
  - `JohnSundell/Splash` (`>= 0.16.0`)
  - `colinc86/MathJaxSwift` (`>= 3.4.0`)
  - `pointfreeco/swift-snapshot-testing` (`>= 1.17.0`)
- File counts at snapshot:
  - Source files (`Sources/MarkdownKit/**/*.swift`): **87**
  - Test files (`Tests/MarkdownKitTests/*.swift`): **75**
  - Docs files (`docs/*.md`): **23**

## 2. Build / Run / Test Commands

### 2.1 Core commands

```bash
swift build
swift test
swift run MarkdownKitDemo
```

### 2.2 High-value verification commands

```bash
# Fast regression gate (recommended default)
bash scripts/verify_fast.sh

# iOS XCTest contracts plus app-hosted real-WebKit Mermaid smoke
bash scripts/verify_ios.sh

# Heavy benchmarks only
bash scripts/verify_benchmarks.sh

# Combined wrapper
bash scripts/verify_all.sh

# Fast syntax + pipeline confidence
swift test --filter SyntaxMatrixTests

# CommonMark resilience + semantic subset
swift test --filter CommonMarkSpecTests

# Security guardrails
swift test --filter URLSanitizerTests
swift test --filter DepthLimitTests
swift test --filter FuzzTests

# Snapshot checks (owned exclusively by scripts/verify_snapshots.sh)
bash scripts/verify_snapshots.sh --visual
bash scripts/verify_snapshots.sh --determinism

# Mermaid adapter sanity
swift test --filter MermaidDiagramAdapterTests

# Heavy benchmark path (Release build, one process per workload)
bash scripts/verify_benchmarks.sh
```

### 2.3 Latest observed results

- `swift test list`: **517** discoverable tests
- `swift test`: **516 tests passed** on 2026-07-18
- `verify_fast.sh`: **499** correctness tests
- `verify_ios.sh`: **550** XCTest tests plus one app-hosted Mermaid PASS marker
- Known noise: deduplicated MathJax warning for `\\binom` may still appear once in benchmark/full runs

## 3. End-to-End Architecture

Pipeline:

1. `MarkdownView` creates `MarkdownRenderInput`; `MarkdownEngine` (`@MainActor`) coalesces single-flight requests (one active detached render + one latest pending request).
2. Parse boundary uses `MarkdownParseKey` (`text` + `resourceLimits` + ordered plugin fingerprint); only matching keys can reuse cached raw AST.
3. On parse misses, task-confined `MarkdownParser` + plugin chain produce a fresh internal `DocumentNode`.
4. Details disclosure overrides are reapplied to the latest configuration before layout.
5. `LayoutSolver.solve(node:width:)` builds attributed content + measured sizes through the internal `TextKitCalculator`. Parser-produced images remain inline: `ImageAttachmentBuilder` loads through `ImageResourceLoader`, builds a bounded thumbnail attachment, or emits bracketed secondary-color alt text.
6. Each `LayoutResult` caches accessibility label, value, hint, role, and task-checkbox state during layout so UIKit/AppKit cells apply metadata without re-scanning attributed strings.
7. `LayoutCache` memoizes `(node.contentFingerprint, optional interaction fingerprint, rounded width, solver variant hash)` results, including image-policy inputs.
8. UI containers mount top-level `LayoutResult` rows (`MarkdownCollectionView` iOS/macOS).
9. Internal hosted views rasterize attributed strings, including inline image attachments, off-main; `AsyncCodeView` handles code rows.

Core goal: move parse/layout cost off the main thread and keep cell sizing effectively O(1) during scrolling.

## 4. Module Knowledge

### 4.1 Parsing layer

Primary files:
- `Sources/MarkdownKit/Parsing/MarkdownParser.swift`
- `Sources/MarkdownKit/Parsing/MarkdownKitVisitor.swift`
- `Sources/MarkdownKit/Parsing/ASTPlugin.swift`
- `Sources/MarkdownKit/Parsing/*ExtractionPlugin.swift`
- `Sources/MarkdownKit/Parsing/Plugins/GitHubAutolinkPlugin.swift`

Key facts:
- Plugin ordering matters.
- `MarkdownParser.ResourceLimits.default` bounds resource usage: `maximumInputBytes` = 1,048,576 UTF-8 bytes (inclusive) and `maximumNestingDepth` = 50. The depth budget only bounds `MarkdownKitVisitor` while mapping an already-parsed `swift-markdown` tree into native nodes: the root document is not counted, and a boundary container remains while its descendants are omitted. It is **not** a `swift-markdown` front-end limit or a layout/rendering depth limit.
- `parseOutcome(_:)` returns `.rejected(diagnostic:)` for oversized input (checked before any `swift-markdown` parsing) and reports depth truncation as a diagnostic on a `.parsed` outcome; it never logs. The legacy `parse(_:) -> DocumentNode` is a lossy compatibility convenience that logs each diagnostic and collapses rejection into the historical empty `DocumentNode`.
- HTML blocks/inlines are preserved as text and optionally reinterpreted by plugins.
- `GitHubAutolinkPlugin` optionally accepts a `MarkdownAutolinkResolver`, retains it strongly, and fingerprints nil-vs-resolver configuration (plus resolver-specific fingerprint state) for render/cache invalidation.

### 4.2 Nodes and security boundary

- Node model is structured and UUID-addressable (`DocumentNode`, `ParagraphNode`, `Table*`, `DetailsNode`, `DiagramNode`, `MathNode`, etc.).
- `LinkNode` and `ImageNode` sanitize URL input through the internal `URLSanitizer` on initialization.
- Image source sanitization does not grant I/O permission; `ImageLoadingPolicy` is enforced separately during layout.

### 4.3 Layout/styling

Primary files:
- `Sources/MarkdownKit/Layout/LayoutSolver.swift`
- `Sources/MarkdownKit/Layout/AttributedStringBuilder.swift`
- `Sources/MarkdownKit/Layout/ArithmeticTextCalculator.swift`
- `Sources/MarkdownKit/Layout/ArithmeticTextScanner.swift`
- `Sources/MarkdownKit/Layout/ArithmeticTextSegmentClassifierMerger.swift`
- `Sources/MarkdownKit/Layout/ArithmeticTextMeasurer.swift`
- `Sources/MarkdownKit/Layout/ArithmeticTextLineBreaker.swift`
- `Sources/MarkdownKit/Layout/Builders/TableLayoutShared.swift`
- `Sources/MarkdownKit/Layout/Builders/TableAttributedStringBuilder.swift`
- `Sources/MarkdownKit/Layout/Builders/TableCardRenderer.swift`
- `Sources/MarkdownKit/Layout/Builders/ImageAttachmentBuilder.swift`
- `Sources/MarkdownKit/Math/DefaultMathRenderingAdapter.swift` (LaTeX → SVG → CGImage)
- `Sources/MarkdownKit/Layout/TextKitCalculator.swift`
- `Sources/MarkdownKit/Layout/LayoutCache.swift`
- `Sources/MarkdownKit/Theme/Theme.swift`

Key facts:
- `LayoutCache` keys are `node.contentFingerprint` + optional interaction fingerprint + rounded width + solver variant hash (theme/diagram/math/image policy/appearance inputs). The separate interaction identity covers source ranges and URLs captured by checkbox/details callbacks without changing semantic stable identity or pixel-render identity.
- `AttributedStringBuilder` classifies block and inline structure once into an invocation-local flat operation program. Sequential async/sync materializers share structural behavior while keeping image, math, and diagram mode differences explicit.
- `LayoutSolver` performs cache lookup before classifying a node into a shallow recipe, then shares immediate output, measurement, color resolution, and `LayoutResult` assembly across its explicit async/sync envelopes.
- The internal `ArithmeticTextCalculator` is the pure-text routing/cache facade. Width-independent preparation streams UTF-16 spans through dedicated scanner, localized classifier/merger, and CoreText measurer value types; `ArithmeticTextLineBreaker` separately owns fit-versus-paint widths, indents, hard breaks, soft hyphens, and oversized-token fallback.
- `TableLayoutShared` owns the immutable canonical rectangular table grid (cell text/display text, alignment, row role/body index) and sanitized uniform column geometry. Three thin adapters intentionally preserve platform-specific visuals: AppKit native `NSTextTableBlock`, UIKit nested attributed tab/narrow fallback, and UIKit top-level `TableCardRenderer` cards drawn through `CGContext`.
- `ImageResourceLoader` is the sole production owner of image source resolution, policy gating, file/`URLSession` loading, pre-follow redirect policy, HTTP status, MIME, expected-byte-count, streamed final-byte limits, and typed rejection.
- `ImageAttachmentBuilder` uses ImageIO to create an oriented, width-constrained thumbnail. Its decoded cache is keyed by policy/source/rounded target width, bounded by count and total cost, and rejects any decoded image above 64 MiB.
- Parser-produced Markdown images are inline attachments only. There is no top-level/block-image layout or visible-cell image loader.
- The internal `TextKitCalculator` safely isolates layout passes to avoid concurrent `NSLayoutManager` data dictionary deadlocks via tight locks.
- Code blocks support optional language badges, Splash tokenization for Swift,
  and regex-based keyword highlighting for the supported non-Swift language
  families. Generic highlighting reuses bounded, theme-independent compiled
  regex bundles while constructing attributed output per source and theme.
- Inline code remains style-focused (no token-level inline lexing).

### 4.4 Diagram/math backends

- Mermaid: `MermaidSnapshotter` owns one MainActor FIFO/cache/cancellation state
  machine. Production and macOS integration tests render through the file-backed
  `WKWebView` using bundled `mermaid.min.js`; app-less iOS XCTest installs a
  deterministic image driver before lazy singleton creation, and
  `verify_ios.sh` separately proves the real backend in a running SwiftUI app.
  Successful intrinsic images are cached by exact source with count/cost bounds;
  width, attachment bounds, failed renders, and canceled requests remain outside
  the cache.
- Math: `DefaultMathRenderingAdapter` uses MathJax → SVG → SwiftDraw rasterization (no WebView). `MathSVGPreprocessor` normalizes `ex` units and `currentColor`.

### 4.5 UI layer

Primary files:
- iOS: `UI/iOS/MarkdownCollectionView_iOS.swift`, `UI/iOS/MarkdownCollectionViewCell.swift`
- Shared components: `UI/Components/AsyncTextView.swift`, `AsyncCodeView.swift`, `UI/SwiftUI/MarkdownRenderCoordinator.swift`
- macOS: `UI/macOS/MarkdownCollectionView_macOS.swift`, `UI/macOS/MarkdownItemView.swift`

Key facts:
- The internal `MarkdownCollectionViewCell` (iOS) and `MarkdownItemView` (macOS) implement Texture-style view layer recycling, maintaining hosted-view allocations and CALayers across high-speed lists.
- Image-policy changes trigger relayout and inline attachment rebuilding; cells do not independently load images when they become visible.
- macOS resize updates are coalesced through effective-content-width reporting plus the SwiftUI coordinator's 200ms debounce/latest-request replacement path.

## 5. Automated Test Strategy (Current State)

High-value suites:
- Parser/plugin correctness: `Parser*Tests`, `ASTPluginTests`, `*ExtractionPluginTests`, `GitHubAutolinkPluginTests`
- Layout invariants: `LayoutSolverExtendedTests`, `InlineFormattingLayoutTests`, `InteractionCacheIdentityTests`, `CrossPlatformLayoutTests`
- Arithmetic preparation/layout contracts: `ArithmeticTextCalculatorTests`
- Table canonicalization/adapters: `TableLayoutSharedTests`, `TableAttributedStringBuilderTests`, `iOSTableLayoutTests`
- Unified image pipeline: `ImageResourceLoaderTests` (12 injected-`URLProtocol`/local policy and validation tests), `ImageAttachmentBuilderTests` (5 decode/cache tests)
- Safety and Utils: `URLSanitizerTests`, `DepthLimitTests`, `FuzzTests`, `TableOfContentsBuilderTests`, `PlatformAccessibilityTests`, `PerformanceProfilerTests`
- Committed visual regression: macOS `SnapshotTests`
- Deferred visual coverage: `iOSSnapshotTests` has no committed baseline or dedicated lane
- Deterministic diagram rendering integration (not image snapshot assertions): `DiagramSnapshotTests`
- Mermaid backend contracts: `MermaidDiagramAdapterTests` uses real WebKit on
  macOS and a deterministic image driver on iOS; the iOS verification script
  adds a separate app-hosted public-`MarkdownView` Mermaid-fence smoke using
  real WebKit after its 550 XCTest tests.
- Benchmarks: `MarkdownKitBenchmarkTests`, `BenchmarkNodeTypeTests`,
  `BenchmarkCacheTests`, `MarkdownRenderCoordinatorBenchmarkTests`

## 6. Known Gaps / Risks / Technical Debt

1. Math conversion warnings (notably `\\binom`) are deduplicated but can still emit one warning per unique failure signature.
2. Generic non-Swift highlighting is intentionally regex/keyword based rather
   than a full grammar for every advertised language family.
3. Full `swift test` feedback loop remains relatively heavy due to benchmark suites.
4. Documentation can drift unless refreshed from repeatable command output.
5. Real iOS WebKit is intentionally outside the app-less XCTest process; the
   current app-hosted gate is a smoke contract rather than a full WebKit
   lifecycle stress suite.

## 7. Extension Points

1. New syntax transform: add an `ASTPlugin` and wire it into parser pipeline.
2. New diagram language: extend `DiagramLanguage` + adapter registry + tests.
3. Styling: evolve `Theme` token surface and apply in `AttributedStringBuilder`.
4. Host-app integration: use `MarkdownAutolinkResolver` for autolink destinations; attachment upload/permalink/custom action/issue-keyword workflows remain host-owned (no renderer hooks).
5. Performance gates: refresh benchmark baseline docs and threshold policies as needed.

## 8. Practical Review Sequence

For broad confidence with reasonable time cost:

1. `swift test --filter SyntaxMatrixTests`
2. `swift test --filter "DetailsExtractionPluginTests|DiagramExtractionPluginTests|MathExtractionPluginTests|GitHubAutolinkPluginTests"`
3. `swift test --filter "LayoutSolverExtendedTests|InlineFormattingLayoutTests|CrossPlatformLayoutTests"`
4. `bash scripts/verify_snapshots.sh --visual` and `bash scripts/verify_snapshots.sh --determinism` (SnapshotTests, owned exclusively by this script)
5. `swift test --filter "URLSanitizerTests|DepthLimitTests|FuzzTests"`
6. (optional heavy) `bash scripts/verify_benchmarks.sh`
