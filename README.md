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

`parser.parse(_:)` is a lossy compatibility convenience: it logs diagnostics and falls back to
an empty (or partially-truncated) document instead of surfacing rejection. Hosts that parse
untrusted or unbounded content should use `parser.parseOutcome(_:)` instead — see
[Parser Resource Limits & Typed Outcomes](#parser-resource-limits--typed-outcomes) below.

## One-Call Convenience

```swift
import MarkdownKit

let layout = await MarkdownKitEngine.layout(
    markdown: "# Hello\n\nThis is **MarkdownKit**.",
    constrainedToWidth: 800
)
print(layout.children.count)
```

Direct layout APIs use a deterministic `.light` appearance by default. Pass
`appearance: .dark` to `makeLayoutSolver` or `MarkdownKitEngine.layout` for
dark output. SwiftUI `MarkdownView` follows the environment `colorScheme`
automatically.

SwiftUI hosts should import both `MarkdownKit` and `SwiftUI`; MarkdownKit does not re-export
SwiftUI. Syntax highlighting is an implementation detail and Splash is not re-exported.

## Markdown Images

Markdown images are inline content. During layout, `ImageAttachmentBuilder` asks the unified
`ImageResourceLoader` to load an allowed source, decodes a width-constrained thumbnail, and
inserts an `NSTextAttachment`. Rejected or undecodable sources render as bracketed,
secondary-color alt text. MarkdownKit does not expose a separate top-level/block-image path.

Image I/O is opt-in:

- `.default` and `.disabled` deny all image I/O.
- `.remoteHTTPS` allows HTTPS sources only and rejects disallowed redirects before following them.
- `.trusted` allows local/relative paths plus HTTP and HTTPS; use it only for trusted content.

Configure the policy on the layout/render surface:

```swift
import MarkdownKit
import SwiftUI

let solver = MarkdownKitEngine.makeLayoutSolver(imageLoadingPolicy: .remoteHTTPS)
let layout = await MarkdownKitEngine.layout(
    markdown: "Logo: ![MarkdownKit](https://example.com/logo.png)",
    constrainedToWidth: 800,
    solver: solver
)

let view = MarkdownView(
    text: "Logo: ![MarkdownKit](https://example.com/logo.png)",
    imageLoadingPolicy: .remoteHTTPS
)
```

`imageLoadingPolicy` is a layout input. Changing it relayouts the document and rebuilds inline
attachments; it does not enable visible-cell image loading. Remote response bodies are streamed
and canceled once `maximumResponseBytes` would be exceeded.

## Parser Resource Limits & Typed Outcomes

`MarkdownParser` uses a per-instance `ResourceLimits` policy to bound accepted input size and
recursive native-AST mapping work. The default policy
(`MarkdownParser.ResourceLimits.default`) is:

- `maximumInputBytes`: 1,048,576 UTF-8 bytes (1 MiB), inclusive — input whose UTF-8 byte count
  equals the limit is accepted; only strictly larger input is rejected.
- `maximumNestingDepth`: 50 — the maximum retained container nesting beneath the root
  `Document`. The root is not counted; at the boundary, the container remains while its
  descendants are omitted. This is **not** a `swift-markdown` front-end parser limit and
  **not** a layout/rendering depth limit.

For untrusted or unbounded input, use the synchronous, non-logging `parseOutcome(_:)` API and
inspect its diagnostics directly instead of relying on the lossy `parse(_:)` convenience:

```swift
import MarkdownKit

let parser = MarkdownParser(limits: .init(maximumInputBytes: 2_000_000, maximumNestingDepth: 80))

switch parser.parseOutcome(untrustedMarkdown) {
case .parsed(let document, let diagnostics):
    // `diagnostics` may report a truncated subtree even though parsing succeeded.
    let layout = await solver.solve(node: document, constrainedToWidth: 800)
case .rejected(let diagnostic):
    // Input exceeded `maximumInputBytes` before any swift-markdown parsing occurred.
    handle(diagnostic)
}
```

`MarkdownParser` itself is synchronous and not `Sendable` (its plugins need not be `Sendable`).
Construct task-confined parser/plugin instances rather than sharing one across concurrent
tasks; host call sites decide whether to invoke it off the main actor.

## SwiftUI Render Coordination

`MarkdownView` funnels updates through `@MainActor` `MarkdownEngine` (`UI/SwiftUI/MarkdownRenderCoordinator.swift`):

- At most one detached parse/layout task is active, plus one latest pending request.
- Every new request immediately invalidates older generations; debounced updates wait 200ms before submit.
- Publication is generation-guarded (`output.generation == latestGeneration`), so stale completions never replace current layouts.
- Raw AST reuse happens only when `MarkdownParseKey` is unchanged (`text`, `resourceLimits`, ordered plugin fingerprint).
- Layout-only dimensions (`width`, `theme`, `appearance`, `diagramRegistry`, `imageLoadingPolicy`) reuse the raw AST and relayout only.
- Details disclosure is reapplied as an override onto the latest configuration before layout, preventing stale-config regressions.

## Autolink Resolver Integration

`MarkdownKitEngine.makeParser(autolinkResolver:includeGitHubAutolinks:)` and
`GitHubAutolinkPlugin(resolver:)` accept an optional `MarkdownAutolinkResolver`:

```swift
final class ImmutableAutolinkResolver: MarkdownAutolinkResolver {
    let ownerRepo: String

    init(ownerRepo: String) {
        self.ownerRepo = ownerRepo
    }

    func resolveMention(username: String) -> URL? {
        URL(string: "https://github.com/\(username)")
    }

    func resolveReference(reference: String) -> URL? {
        guard reference.hasPrefix("#") else {
            return URL(string: "https://github.com/\(reference)")
        }
        return URL(string: "https://github.com/\(ownerRepo)/issues/\(reference.dropFirst())")
    }

    func resolveCommit(sha: String) -> URL? {
        URL(string: "https://github.com/\(ownerRepo)/commit/\(sha)")
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: Self.self))
        hasher.combine(ownerRepo)
    }
}

let parser = MarkdownKitEngine.makeParser(
    autolinkResolver: ImmutableAutolinkResolver(ownerRepo: "apple/swift"),
    includeGitHubAutolinks: true
)
```

Guidance:
- `GitHubAutolinkPlugin` strongly retains its resolver. Use a dedicated resolver object and avoid a cycle in which it also retains the parser/plugin graph.
- Resolver methods are synchronous and may run off-main during detached render work, so resolver state must be immutable or explicitly synchronized. A main-actor UI model should not conform directly.
- Include all output-affecting resolver configuration in `cacheFingerprint(into:)` so SwiftUI render identity invalidates when resolver behavior changes.
- UI interactions (link taps, checkbox toggles, details disclosure) remain view-owned via closures like `onLinkTap` and `onCheckboxToggle`.
- The deprecated `MarkdownContextDelegate` name and `contextDelegate:` labels remain migration shims, but conformers must satisfy the new `Sendable` contract.

## Automated Verification

Fast regression gate (recommended for daily iteration, correctness-only in every environment):

```bash
bash scripts/verify_fast.sh
```

Platform public API baselines:

```bash
bash scripts/verify_public_api.sh --platform macos --check
bash scripts/verify_public_api.sh --platform ios-simulator --check
```

After an intentional, reviewed public API change or an approved toolchain update, regenerate the
matching baseline explicitly:

```bash
bash scripts/verify_public_api.sh --platform macos --record
bash scripts/verify_public_api.sh --platform ios-simulator --record
```

`PublicAPISmokeTests` remains the fast normal-import compile and behavior contract for a consumer.
The committed symbol-graph baselines in `API/PublicAPI/` contain every source-declared public
symbol plus its compiler-emitted public relationships, including protocol requirements,
extensions, overloads, availability, inherited platform conformances, and platform-conditional
APIs. The iOS gate verifies both arm64 and x86_64 Simulator graphs against one
architecture-neutral baseline. Recording is intentionally explicit and pinned to Xcode 26.4.1;
review baseline diffs rather than treating `--record` as normal verification.

Strict documentation freshness gate:

```bash
bash scripts/check_doc_freshness.sh
```

Release metadata / provenance gate:

```bash
bash scripts/verify_provenance.sh
```

The wrapper first resolves the package graph from `Package.swift`, then runs the
offline Python verifier against `Package.resolved`, checked-in legal files, and
vendored-resource policy anchors. See
[`docs/MERMAID_PROVENANCE.md`](docs/MERMAID_PROVENANCE.md) for the separate,
networked Mermaid rebuild and inventory-refresh procedure.

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

`verify_all.sh` always resolves dependencies and runs the provenance gate first, then checks both
platform API baselines. `--full` uses `swift test` instead of the fast correctness split.
Release owners should use the complete [release procedure](docs/RELEASE.md), not this convenience
wrapper alone.

Optional heavy benchmark suites:

```bash
bash scripts/verify_all.sh --with-benchmarks
```

One-shot full suite (includes all tests, including benchmarks/snapshots):

```bash
bash scripts/verify_all.sh --full
```

iOS Simulator correctness lane: `verify_ios.sh` creates a package-only workspace from
`Package.swift`, `Package.resolved`, `Sources`, and `Tests`, then runs the package's tests with
`xcodebuild` against an iOS Simulator matching the active Xcode iPhone Simulator SDK. The app-less
XCTest process runs the 10 Mermaid state-machine contracts with an explicitly injected
deterministic image backend, so it never constructs `WKWebView`. After all 674 XCTest tests pass,
the script assembles the SwiftPM demo executable into an ad-hoc-signed Simulator app and requires
exactly one PASS marker after a Mermaid fence travels through the public `MarkdownView` pipeline
and its registry-backed real WebKit adapter. The smoke is additional and is not counted as XCTest.
Set `MARKDOWNKIT_IOS_SIMULATOR_UDID` to explicitly override simulator selection:

```bash
bash scripts/verify_ios.sh
```

### Test Split Strategy

Verification is split into seven honestly-scoped contracts rather than one monolithic test run:

- **Provenance gate** (`verify_provenance.sh`, all CI jobs): Resolves the manifest-derived package graph before invoking the read-only, offline `verify_provenance.py` drift check for `Package.resolved`, the vendored Mermaid artifact, and checked-in third-party notice coverage.
- **Correctness gate** (`verify_fast.sh`, CI job `verify`): Discovers every `XCTestCase` suite in `MarkdownKitTests` via `swift test list` and runs all of them except the benchmark suites and the two true snapshot suites (`SnapshotTests`, `iOSSnapshotTests`). It is correctness-only in every environment — it never records or verifies snapshots, locally or in CI — so newly added test classes are covered automatically instead of relying on a hand-maintained allow-list. `DiagramSnapshotTests` is a deterministic suite and stays in this gate.
- **Public API graph baselines** (`verify_public_api.sh`, macOS `verify` and iOS `verify-ios` CI jobs): SwiftPM builds and `swift-symbolgraph-extract` produce every source-declared public symbol and its compiler-emitted public relationships for macOS 26.0 and iOS 17.0 Simulator. The iOS gate checks both simulator architectures. `PublicAPISmokeTests` remains the complementary fast normal-import compile/behavior contract. Checks are read-only; recording a baseline is an intentional, reviewed Xcode 26.4.1 operation.
- **Documentation freshness gate** (`check_doc_freshness.sh`, CI job `verify`): A strict, Bash 3.2-compatible, read-only check that the discoverable test count and generated benchmark docs match their sources. Runs after the correctness gate as its own explicit CI step.
- **Snapshot contracts** (`verify_snapshots.sh`, CI job `verify-snapshots`): Owns `SnapshotTests` exclusively, split into two independent, honestly-labeled modes:
  - `--visual` diffs the current run against the *committed* baseline PNGs. Although Xcode is pinned, the `macos-26` runner's fonts and OS point releases can still move under us, so this is a genuine visual-regression signal but is **non-blocking** (`continue-on-error: true`) since environment drift alone can flip it.
  - `--determinism` records fresh baselines and immediately re-verifies against them in the *same* run/environment, then restores the original snapshot directory. This proves the renderer is internally deterministic and is **blocking**.
  - `iOSSnapshotTests` currently has no committed baseline or dedicated CI lane; it is intentionally excluded from both `verify_fast.sh` and `verify_snapshots.sh` and should not be read as covered by either gate.
- **iOS Simulator suite** (`verify_ios.sh`, CI job `verify-ios`): Discovers the same correctness suites by scanning source (minus benchmarks and true snapshot suites), verifies the compiled iOS test bundle contains every UIKit-bearing suite, and runs exactly 674 tests via `xcodebuild` on an SDK-matched iOS Simulator (unless `MARKDOWNKIT_IOS_SIMULATOR_UDID` explicitly overrides it), with exact enumeration/execution validation, per-test timeouts, crash/restart detection, and a private system-font fallback check. Mermaid's FIFO/cache/cancellation contracts use an explicit deterministic image driver only in this app-less XCTest host. The same script then builds and packages the SwiftPM demo product, launches it with a real `UIApplication`, and requires exactly one PASS marker from a Mermaid fence rendered through public `MarkdownView` and a registry-backed real-WebKit adapter.
- **Benchmark suite** (`verify_benchmarks.sh`): Heavy performance regression tests. Run locally or through deliberately configured manual/scheduled automation; they are not part of PR CI. The gate first checks that `docs/BENCHMARK_BASELINE.md` is up to date with `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json` (the authoritative, machine-readable baseline consumed by both the docs and `BenchmarkRegressionGuard`) via `python3 scripts/render_benchmark_baseline.py --check`, then builds the test bundle once in Release and launches 13 canonical isolated Release workloads in their own processes. `BenchmarkPreparedContentTests` measures true-cold first solve, persistent width sweep, and a rebuild control whose fresh solvers are constructed outside timing; the permanent guard requires persistent avg and p95 <=60% of the rebuild control. After editing the baseline JSON, refresh the doc with `python3 scripts/render_benchmark_baseline.py`.
- Running bare `swift test` executes everything including benchmarks and true snapshot suites. Prefer `verify_fast.sh` for daily iteration.

## Project Structure

- `Sources/MarkdownKit`: core parser, AST nodes, plugins, layout engine, UI components
- `Sources/MarkdownKitDemo`: demo app
- `Tests/MarkdownKitTests`: unit/integration tests
- `API/PublicAPI`: committed macOS and iOS Simulator public symbol-graph baselines
- `ThirdParty/`: checked-in third-party licenses/notices and `provenance.lock.json`
- `docs/`: PRD, feature notes, roadmap, and the [release procedure](docs/RELEASE.md)
- `scripts/`: local automation and verification entrypoints
- `tasks/`: implementation checklist

## License

MarkdownKit is licensed under the MIT License. Third-party redistribution notices live in
`THIRD_PARTY_NOTICES.md`, and the machine-readable dependency/resource provenance lock lives at
`ThirdParty/provenance.lock.json`. See [CHANGELOG.md](CHANGELOG.md) for consumer-facing release
changes and migration notes.
