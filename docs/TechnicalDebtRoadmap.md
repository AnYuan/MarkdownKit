# Technical Debt Roadmap (as of 2026-03-04)

## Current Health Snapshot

- `swift test`: **227+ tests executed, 0 failures** (latest local run).
- Snapshot drift issue on macOS has been stabilized by fixing test appearance constraints.
- Mermaid adapter/API mismatch (`MermaidHTMLBuilder.makeHTML`) has been repaired.
- Public API facade (`MarkdownKitEngine`) is already available and documented in README.
- `SplashHighlighter` now supports generic keyword highlighting for ~30 common languages (Python, JS, Go, Rust, etc.).
- Concurrency boundaries are documented in `docs/ConcurrencyContract.md` and stress-tested in `ConcurrencyStressTests`.
- `MathWarningSuppressor` now has a capacity limit (128 entries, FIFO eviction) to prevent unbounded memory growth.
- Documentation freshness can be checked via `scripts/check_doc_freshness.sh`.

## Resolved Debt Items

| Debt Item | Resolution |
|---|---|
| MathJax warning suppressor unbounded growth | Added capacity limit (128) with FIFO eviction; tested in `MathWarningSuppressorTests` |
| Concurrency stress coverage gaps | Added `ConcurrencyStressTests` covering concurrent LayoutSolver, LayoutCache, and parser thread safety |
| Syntax highlighting Swift-only | Added `GenericKeywordHighlighter` with regex-based keyword/string/comment coloring for ~30 languages; unlabeled code no longer defaults to Swift |
| iOS table cell overflow | Added character-level truncation with ellipsis for both tab-stop and narrow-fallback modes |
| Verification cost documentation | Added test split strategy docs in README; fast/heavy paths already existed |
| Documentation drift | Refreshed CodebaseKnowledge.md, FeatureMatrix.md, TestCoverage.md; added `check_doc_freshness.sh` script |
| Monolithic AttributedStringBuilder | Extracted logic into `TableAttributedStringBuilder`, `ImageAttachmentBuilder`, and `MathAttachmentBuilder` for better modularity and testability. |
| LayoutSolver/TextKit Concurrency Deadlocks | Extracted TextKit instances per calculation pass, removed global states, and protected NSTextStorage C-level cache dictionary evaluations via `os_unfair_lock` under high load. |
| Slow UI layer view allocation | Implemented asynchronous view recycling (`MarkdownCollectionViewCell/MarkdownItemView`), matching `Texture/AsyncDisplayKit` continuous-allocation optimization best practices. |
| Test Coverage Gaps | Reached 82.03% line coverage by establishing robust test suites covering utility files (`TableOfContentsBuilder`, `PerformanceProfiler`, and `PlatformAccessibility`). |

## Remaining Debt (Lower Priority)

| Priority | Debt Item | Current Impact | Recommended Action |
|---|---|---|---|
| P3 | iOS table still uses tab-stop emulation (no NSTextTable equivalent) | Visual parity gap vs macOS for complex tables | Accept as platform limitation; document in FeatureMatrix |
| P3 | Syntax highlighting limited to keyword/string/comment tokens | No AST-level tokenization for non-Swift languages | Evaluate tree-sitter Swift bindings if deeper highlighting is needed |
| P3 | Documentation can still drift over time | Mitigated by freshness check script | Consider CI integration of `check_doc_freshness.sh` |
