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

Fast regression gate (recommended for daily iteration, correctness-only in every environment):

```bash
bash scripts/verify_fast.sh
```

Strict documentation freshness gate:

```bash
bash scripts/check_doc_freshness.sh
```

Snapshot contracts (macOS only, two independent modes — see below):

```bash
bash scripts/verify_snapshots.sh --visual
bash scripts/verify_snapshots.sh --determinism
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

CI enforces four separate, honestly-scoped contracts rather than one monolithic test run:

- **Correctness gate** (`verify_fast.sh`, CI job `verify`): Discovers every `XCTestCase` suite in `MarkdownKitTests` via `swift test list` and runs all of them except the benchmark suites and the two true snapshot suites (`SnapshotTests`, `iOSSnapshotTests`). It is correctness-only in every environment — it never records or verifies snapshots, locally or in CI — so newly added test classes are covered automatically instead of relying on a hand-maintained allow-list. `DiagramSnapshotTests` is a deterministic suite and stays in this gate.
- **Documentation freshness gate** (`check_doc_freshness.sh`, CI job `verify`): A strict, Bash 3.2-compatible, read-only check that the discoverable test count and generated benchmark docs match their sources. Runs after the correctness gate as its own explicit CI step.
- **Snapshot contracts** (`verify_snapshots.sh`, CI job `verify-snapshots`): Owns `SnapshotTests` exclusively, split into two independent, honestly-labeled modes:
  - `--visual` diffs the current run against the *committed* baseline PNGs. Because CI runs on `macos-26`/`latest-stable` — a rendering environment that moves under us (fonts, OS point releases) — this is a genuine visual-regression signal but is **non-blocking** (`continue-on-error: true`) since environment drift alone can flip it.
  - `--determinism` records fresh baselines and immediately re-verifies against them in the *same* run/environment, then restores the original snapshot directory. This proves the renderer is internally deterministic and is **blocking**.
  - `iOSSnapshotTests` currently has no committed baseline or dedicated CI lane; it is intentionally excluded from both `verify_fast.sh` and `verify_snapshots.sh` and should not be read as covered by either gate.
- **iOS Simulator suite** (`verify_ios.sh`, CI job `verify-ios`): Discovers the same correctness suites by scanning source (minus benchmarks and true snapshot suites), verifies the compiled iOS test bundle contains every UIKit-bearing suite, and runs the enumerated tests on a dynamically-selected iOS Simulator via `xcodebuild`, with exact executed-count validation, per-test timeouts, crash/restart detection, and a private system-font fallback check.
- **Benchmark suite** (`verify_benchmarks.sh`): Heavy performance regression tests. Run locally or through deliberately configured manual/scheduled automation; they are not part of PR CI. The gate first checks that `docs/BENCHMARK_BASELINE.md` is up to date with `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json` (the authoritative, machine-readable baseline consumed by both the docs and `BenchmarkRegressionGuard`) via `python3 scripts/render_benchmark_baseline.py --check`, failing fast before any timing suite runs if the baseline is malformed or the doc is stale. After editing the baseline JSON, refresh the doc with `python3 scripts/render_benchmark_baseline.py`.
- Running bare `swift test` executes everything including benchmarks and true snapshot suites. Prefer `verify_fast.sh` for daily iteration.

## Project Structure

- `Sources/MarkdownKit`: core parser, AST nodes, plugins, layout engine, UI components
- `Sources/MarkdownKitDemo`: demo app
- `Tests/MarkdownKitTests`: unit/integration tests
- `docs/`: PRD, feature notes, roadmap
- `scripts/`: local automation and verification entrypoints
- `tasks/`: implementation checklist
