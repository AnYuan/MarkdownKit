# MarkdownKit Codebase Knowledge (2026-03-04)

This document is a practical snapshot of the current repository, with emphasis on commands, architecture, and known risks that are still actionable.

## 1. Repository Snapshot

- Branch at snapshot: `codex/docs-refresh-20260304-064504`
- HEAD at snapshot: `105e51f`
- Swift tools: `6.2`
- Platforms: `iOS 17+`, `macOS 26.0+`
- Dependencies:
  - `apple/swift-markdown` (branch `main`)
  - `JohnSundell/Splash` (`>= 0.16.0`)
  - `colinc86/MathJaxSwift` (`>= 3.4.0`)
  - `pointfreeco/swift-snapshot-testing` (`>= 1.17.0`)
- File counts at snapshot:
  - Source files (`Sources/MarkdownKit/**/*.swift`): **54**
  - Test files (`Tests/MarkdownKitTests/*.swift`): **48**
  - Docs files (`docs/*.md`): **16**

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

# Snapshot checks
swift test --filter SnapshotTests

# Mermaid adapter sanity
swift test --filter MermaidDiagramAdapterTests

# Heavy benchmark path
swift test --filter MarkdownKitBenchmarkTests/testBenchmarkFullReport
swift test --filter BenchmarkNodeTypeTests/testDeepBenchmarkFullReport
```

### 2.3 Latest observed results

- `swift test list`: **218** discoverable tests
- `swift test`: **218 executed, 0 failures**
- Known noise: deduplicated MathJax warning for `\\binom` may still appear once in benchmark/full runs

## 3. End-to-End Architecture

Pipeline:

1. `MarkdownParser.parse(_:)`
2. `swift-markdown` produces `Document`
3. `MarkdownKitVisitor` maps to internal `MarkdownNode` structs
4. `ASTPlugin` chain rewrites AST (`Details`, `Diagram`, `Math`, optional `GitHubAutolink`)
5. `LayoutSolver.solve(node:width:)` builds attributed content + measured sizes (`TextKitCalculator`)
6. `LayoutCache` memoizes `(nodeID, width-bucket)` results
7. UI containers mount `LayoutResult` rows (`MarkdownCollectionView` iOS/macOS)
8. Async node views render text/code/image (`AsyncTextView`, `AsyncCodeView`, `AsyncImageView`)

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
- Visitor enforces recursion depth via `maxDepth` (default 50).
- HTML blocks/inlines are preserved as text and optionally reinterpreted by plugins.

### 4.2 Nodes and security boundary

- Node model is structured and UUID-addressable (`DocumentNode`, `ParagraphNode`, `Table*`, `DetailsNode`, `DiagramNode`, `MathNode`, etc.).
- `LinkNode` and `ImageNode` sanitize URL input through `URLSanitizer` on initialization.

### 4.3 Layout/styling

Primary files:
- `Sources/MarkdownKit/Layout/LayoutSolver.swift`
- `Sources/MarkdownKit/Layout/AttributedStringBuilder.swift`
- `Sources/MarkdownKit/Layout/TextKitCalculator.swift`
- `Sources/MarkdownKit/Layout/LayoutCache.swift`
- `Sources/MarkdownKit/Theme/Theme.swift`

Key facts:
- `LayoutCache` now uses deterministic width bucketing for hash/equality consistency.
- Code blocks support optional language badge + Splash highlighting.
- Inline code remains style-focused (no token-level inline lexing).

### 4.4 Diagram/math backends

- Mermaid: `MermaidDiagramAdapter` renders via `WKWebView` snapshot flow using bundled `mermaid.min.js` resource.
- Math: `MathRenderer` uses MathJax -> SVG -> snapshot pipeline.

### 4.5 UI layer

Primary files:
- iOS: `UI/iOS/MarkdownCollectionView_iOS.swift`, `UI/iOS/MarkdownCollectionViewCell.swift`
- Shared components: `UI/Components/AsyncTextView.swift`, `AsyncCodeView.swift`, `AsyncImageView.swift`
- macOS: `UI/macOS/MarkdownCollectionView_macOS.swift`, `UI/macOS/MarkdownItemView.swift`

## 5. Automated Test Strategy (Current State)

High-value suites:
- Parser/plugin correctness: `Parser*Tests`, `ASTPluginTests`, `*ExtractionPluginTests`, `GitHubAutolinkPluginTests`
- Layout invariants: `LayoutSolverExtendedTests`, `InlineFormattingLayoutTests`, `CrossPlatformLayoutTests`, `iOSTableLayoutTests`
- Safety: `URLSanitizerTests`, `DepthLimitTests`, `FuzzTests`
- Visual regression: `SnapshotTests`, `iOSSnapshotTests`, `DiagramSnapshotTests`
- Benchmarks: `MarkdownKitBenchmarkTests`, `BenchmarkNodeTypeTests`, `BenchmarkCacheTests`

## 6. Known Gaps / Risks / Technical Debt

1. Math conversion warnings (notably `\\binom`) are deduplicated but can still emit one warning per unique failure signature.
2. Syntax highlighting is currently Swift-only; explicit non-Swift fenced languages now fall back to plain code styling.
3. iOS table rendering is still text/tab based, with lower visual richness than macOS table blocks.
4. Full `swift test` feedback loop remains relatively heavy due to benchmark suites.
5. Documentation can drift unless refreshed from repeatable command output.
6. Concurrency constraints are documented (`docs/ConcurrencyContract.md`) but multi-actor stress coverage can be expanded.

## 7. Extension Points

1. New syntax transform: add an `ASTPlugin` and wire it into parser pipeline.
2. New diagram language: extend `DiagramLanguage` + adapter registry + tests.
3. Styling: evolve `Theme` token surface and apply in `AttributedStringBuilder`.
4. Host-app integration: use `MarkdownContextDelegate` hooks for link/autolink behaviors.
5. Performance gates: refresh benchmark baseline docs and threshold policies as needed.

## 8. Practical Review Sequence

For broad confidence with reasonable time cost:

1. `swift test --filter SyntaxMatrixTests`
2. `swift test --filter "DetailsExtractionPluginTests|DiagramExtractionPluginTests|MathExtractionPluginTests|GitHubAutolinkPluginTests"`
3. `swift test --filter "LayoutSolverExtendedTests|InlineFormattingLayoutTests|CrossPlatformLayoutTests|SnapshotTests"`
4. `swift test --filter "URLSanitizerTests|DepthLimitTests|FuzzTests"`
5. (optional heavy) `swift test --filter MarkdownKitBenchmarkTests/testBenchmarkFullReport`
