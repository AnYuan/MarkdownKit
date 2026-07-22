# Changelog

All notable changes to MarkdownKit are documented in this file.

## [Unreleased]

### Performance

- Release cache lookups no longer update test-only calculator/LayoutCache diagnostics, and
  arithmetic segment widths use a bounded typed FIFO without interpolated keys or boxed values.

### Release engineering

- The app-hosted iOS Mermaid smoke now sends a Mermaid fence through the public `MarkdownView`
  pipeline and a registry-backed real-WebKit adapter instead of invoking the adapter directly.

## [0.4.0] - 2026-07-18

### Migration notes

This is a pre-1.0 release and includes intentional API breaks.

- SwiftUI integrations must import both `MarkdownKit` and `SwiftUI`. MarkdownKit no longer
  re-exports SwiftUI or Splash.
- Replace custom autolink integrations with `MarkdownAutolinkResolver` and implement
  `cacheFingerprint(into:)` for output-affecting configuration. Resolver state must be immutable
  or synchronized because the protocol is `Sendable`; `GitHubAutolinkPlugin` now strongly retains
  its resolver, so avoid retain cycles. `MarkdownContextDelegate` and `contextDelegate:` remain
  deprecated migration shims.
- `MarkdownParser.maxInputBytes` was removed. Pass `ResourceLimits` to `MarkdownParser(limits:)`
  or `MarkdownKitEngine.makeParser(resourceLimits:)`, and use `parseOutcome(_:)` when a host needs
  typed rejection or depth-truncation diagnostics. The default depth budget is 50; `parse(_:)`
  remains a lossy compatibility convenience.
- Images now use one inline, opt-in image-loading pipeline. The synthetic block
  `AsyncImageView` surface and `MarkdownCollectionView.imageLoadingPolicy` were removed. Configure
  image loading on the `LayoutSolver` or `MarkdownKitEngine.makeLayoutSolver`, re-solve, and then
  assign layouts; collection cells no longer initiate image I/O.
- Implementation-only parsing and rendering APIs are internal. `LayoutResult` is a slimmer
  consumer result; depend on the documented public surface rather than implementation details.

### Added

- Appearance-aware layout APIs with deterministic direct-layout appearance and automatic SwiftUI
  color-scheme handling.
- Per-parser resource limits and typed parse outcomes for hosts accepting untrusted or unbounded
  Markdown.
- Public API smoke coverage and platform-specific public symbol-graph contracts.

### Changed

- Markdown images load as width-constrained inline attachments through the shared image pipeline.
- SwiftUI rendering coalesces updates, reuses parsed ASTs for layout-only changes, and preserves
  the latest details configuration.
- `swift-markdown` is pinned to 0.8.0.

### Fixed

- Nested block math is transformed consistently.
- Numeric identifiers no longer become false-positive commit autolinks.
- Synchronous layout matches asynchronous interaction and cache semantics.
- Mermaid rendering awaits its WebKit work before completing.
- Mermaid source is decoded as UTF-8 before rendering, preserving non-ASCII labels.
- System font traits are derived without private-font fallback behavior.

### Security

- Parser input size and nesting depth are bounded by an immutable per-instance policy.
- Image I/O is denied by default; the HTTPS policy validates redirects and bounds streamed
  response bodies.
- Third-party licensing and vendored-resource provenance are checked against committed metadata.

### Performance

- Repeated syntax highlighting and Mermaid diagram work are cached.
- SwiftUI render work is coalesced, and layout-only updates avoid unnecessary reparsing.
- macOS accessibility metadata is reused during item configuration.

### Release engineering

- Added macOS and iOS Simulator public API baseline checks, with both iOS Simulator
  architectures verified against one contract.
- Added reproducible provenance, documentation freshness, snapshot determinism, and iOS
  Simulator correctness gates.
- Split Mermaid verification at the real host boundary: deterministic queue/cache/cancellation
  coverage in app-less iOS XCTest, followed by a blocking app-hosted WebKit smoke.
- Benchmark thresholds now use a machine-readable authoritative baseline.

[Unreleased]: https://github.com/AnYuan/MarkdownKit/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/AnYuan/MarkdownKit/compare/0.03...v0.4.0
