# Copilot instructions for MarkdownKit

## Commands

- Build: `swift build`
- Run the demo executable: `swift run MarkdownKitDemo`
- Recommended fast regression gate: `bash scripts/verify_fast.sh`
- Full test suite, including benchmarks and snapshots: `swift test` or `bash scripts/verify_all.sh --full`
- Heavy benchmark gate only: `bash scripts/verify_benchmarks.sh`
- Combined gate: `bash scripts/verify_all.sh`; add `--with-benchmarks` for heavy benchmark suites
- Run one test suite: `swift test --filter URLSanitizerTests`
- Run one XCTest method: `swift test --filter URLSanitizerTests/testSafeSchemesAllowed`
- Fresh-environment snapshot check follows CI's record-then-verify flow:
  `rm -rf Tests/MarkdownKitTests/__Snapshots__/SnapshotTests/*.png && swift test --filter "SnapshotTests" || true && swift test --filter "SnapshotTests"`

## Architecture

MarkdownKit is a Swift 6.2 package for iOS 17+ and macOS 26.0+. The public entry point is `MarkdownKitEngine` in `Sources/MarkdownKit/MarkdownKit.swift`, which wires parsing, the default plugin pipeline, layout solving, and one-call `layout(markdown:constrainedToWidth:)`.

The rendering pipeline is:

1. `MarkdownParser.parse(_:)` parses raw Markdown with `swift-markdown`.
2. `MarkdownKitVisitor` maps Apple's syntax tree into MarkdownKit's internal `MarkdownNode` model.
3. `ASTPlugin` transforms run in order. The default order is `DetailsExtractionPlugin`, `DiagramExtractionPlugin`, `MathExtractionPlugin`, then optional `GitHubAutolinkPlugin`.
4. `LayoutSolver` converts nodes into styled, immutable `LayoutResult` trees with attributed strings, measured sizes, and child layout results.
5. `LayoutCache` memoizes results by node `contentFingerprint`, rounded width, and a variant hash derived from theme/diagram/math/image policy inputs.
6. SwiftUI and platform collection views mount top-level `LayoutResult.children` using diffable data sources keyed by `StableNodeIdentity`.

Core source areas:

- `Sources/MarkdownKit/Parsing`: `swift-markdown` visitor, mappers, and AST plugins.
- `Sources/MarkdownKit/Nodes`: immutable `Sendable` AST models and security boundaries for links/images.
- `Sources/MarkdownKit/Layout`: attributed string construction, TextKit/arithmetic measurement, cache fingerprinting, and layout results.
- `Sources/MarkdownKit/UI`: SwiftUI wrapper plus iOS/macOS virtualized collection views and async rendering components.
- `Sources/MarkdownKit/Math` and `Sources/MarkdownKit/Diagrams`: MathJax/SwiftDraw math rendering and host-provided diagram adapter registry.

## Codebase conventions

- Keep parser/plugin ordering intentional. If adding syntax support, prefer a new `ASTPlugin` and wire it through `MarkdownKitEngine.defaultPlugins(...)` only when it should be part of the default pipeline.
- Every `MarkdownNode` conformer must compute `contentFingerprint` at initialization with `_markdownNodeFingerprint(...)`. Use a literal type name, include semantic own fields, read only direct child `contentFingerprint` values, and never include the per-parse `UUID`.
- `LinkNode` and `ImageNode` sanitize destinations at initialization through `URLSanitizer`; do not bypass this when adding link/image-producing mappers or plugins.
- Image loading is opt-in through `ImageLoadingPolicy`. The default policy blocks image I/O; host-facing APIs should preserve that conservative default unless callers explicitly choose `remoteHTTPS`, `trusted`, or a custom policy.
- Layout work is designed to run off the main thread and return UI-detached `LayoutResult` values. Keep UIKit/AppKit mutations on the main actor and keep cell sizing O(1) by using precomputed `LayoutResult.size`.
- The SwiftUI `MarkdownView` keeps parse/layout work in a cancellable off-main render task and reuses a persistent `LayoutCache` while theme, diagram registry, and image policy are unchanged.
- iOS/macOS collection views use diffable data sources keyed by `StableNodeIdentity` rather than `MarkdownNode.id`, because node UUIDs are regenerated on every parse.
- Mermaid rendering uses `WKWebView` and must stay on `MainActor`; math rendering goes through the `MathRenderingAdapter` abstraction and the default adapter's actor-backed MathJax pipeline.
- Snapshot tests are environment-sensitive. Use the CI record-then-verify pattern when baselines need to be refreshed for a new OS/font/rendering stack.
- Benchmark tests are intentionally heavier than the fast gate and include regression guardrails in `BenchmarkRegressionGuard`.
- Existing repo agent guidance in `GEMINI.md` asks agents to plan non-trivial work, verify before declaring completion, keep changes minimal, and update `tasks/lessons.md` after user corrections. If changes affect project requirements or tracked work, keep `docs/PRD.md` and `tasks/todo.md` aligned.
