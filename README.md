# MarkdownKit

MarkdownKit is a high-performance native Markdown renderer for Apple platforms, built in Swift with `swift-markdown` and TextKit-based layout.

## Highlights

- CommonMark + GitHub Flavored Markdown (tables, task lists, strikethrough, links)
- Native table rendering (`NSTextTable`) with GitHub-like styling
- Math support (`$...$`, `$$...$$`, and fenced `math`) via MathJaxSwift
- Collapsed sections support (`<details>/<summary>`)
- Diagram fence detection (`mermaid`, `geojson`, `topojson`, `stl`) with pluggable adapter fallback
- Async layout pipeline and virtualized iOS/macOS collection views

## Requirements

- Swift 6.2+
- iOS 17.0+
- macOS 26.0+

## Quick Start

```bash
swift build
swift test
swift run MarkdownKitDemo
```

## Basic Usage

```swift
import MarkdownKit

let parser = MarkdownKitEngine.makeParser()
let solver = MarkdownKitEngine.makeLayoutSolver()

let document = parser.parse("# Hello MarkdownKit")
let layout = await solver.solve(node: document, constrainedToWidth: 800)
print(layout.children.count)
```

## One-Call Convenience

```swift
import MarkdownKit

let layout = await MarkdownKitEngine.layout(
    markdown: "# Hello\n\nThis is **MarkdownKit**.",
    constrainedToWidth: 800
)
print(layout.children.count)
```

## Automated Verification

Fast regression gate (recommended for daily iteration):

```bash
bash scripts/verify_fast.sh
```

Benchmark-only gate (heavier):

```bash
bash scripts/verify_benchmarks.sh
```

Combined wrapper (fast + optional heavy):

```bash
bash scripts/verify_all.sh
```

Optional heavy benchmark suites:

```bash
bash scripts/verify_all.sh --with-benchmarks
```

One-shot full suite (includes all tests, including benchmarks/snapshots):

```bash
bash scripts/verify_all.sh --full
```

iOS Simulator correctness lane (builds and runs the package's tests with `xcodebuild` against a dynamically-selected iOS Simulator, since the tracked `MarkdownKit.xcodeproj` has no test action):

```bash
bash scripts/verify_ios.sh
```

### Test Split Strategy

The test suite is split into fast regression tests and heavy benchmarks:

- **Fast suite** (`verify_fast.sh`): Discovers every `XCTestCase` suite in `MarkdownKitTests` via `swift test list` and runs all of them except the benchmark suites and the two true snapshot suites (`SnapshotTests`, `iOSSnapshotTests`), so newly added test classes are covered automatically instead of relying on a hand-maintained allow-list. This is the complete macOS correctness gate; used as the CI gate.
- **Benchmark suite** (`verify_benchmarks.sh`): Heavy performance regression tests. Run locally or in nightly CI. It first checks that `docs/BENCHMARK_BASELINE.md` is up to date with `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json` (the authoritative, machine-readable baseline consumed by both the docs and `BenchmarkRegressionGuard`) via `python3 scripts/render_benchmark_baseline.py --check`, failing fast before any timing suite runs if the baseline is malformed or the doc is stale. After editing the baseline JSON, refresh the doc with `python3 scripts/render_benchmark_baseline.py`.
- **iOS Simulator suite** (`verify_ios.sh`): Discovers the same correctness suites by scanning source (minus benchmarks and true snapshot suites), verifies the compiled iOS test bundle contains every UIKit-bearing suite, and runs the enumerated tests on a dynamically-selected iOS Simulator via `xcodebuild`, with exact executed-count validation, per-test timeouts, crash/restart detection, and a private system-font fallback check, as a separate CI job.
- Running bare `swift test` executes everything including benchmarks. Prefer `verify_fast.sh` for daily iteration.

## Project Structure

- `Sources/MarkdownKit`: core parser, AST nodes, plugins, layout engine, UI components
- `Sources/MarkdownKitDemo`: demo app
- `Tests/MarkdownKitTests`: unit/integration tests
- `docs/`: PRD, feature notes, roadmap
- `scripts/`: local automation and verification entrypoints
- `tasks/`: implementation checklist
