# Technical Debt Roadmap (as of 2026-02-27)

## Current Health Snapshot

- `swift test` result: `165` tests executed, all passing.
- Table rendering strategy is now aligned across code/tests/docs: native `NSTextTable` blocks with GitHub-like cell styling.
- Test coverage significantly expanded: 22 test files covering parsing, layout, inline formatting, macOS UI, plugin edge cases, and end-to-end integration.

## Prioritized Debt List

| Priority | Debt Item | Current Impact | Recommended Action | Done Criteria |
|---|---|---|---|---|
| P0 | (Resolved) Table rendering strategy mismatch (code vs test vs docs) | Previously caused CI red and ambiguity | Canonicalized to native `NSTextTable` rendering in implementation, tests, and docs | `swift test` all green; single documented table strategy |
| P0 | Public API facade is empty (`MarkdownKit.swift`) | Integration path for consumers is unclear | Add a minimal stable facade (`parse + layout + render model`) and keep internals behind it | External caller can render markdown without touching internal classes directly |
| P1 | Math rendering parity and determinism | UIKit/macOS behavior can diverge; snapshot sizing is fallback-based | Unify platform behavior, make size extraction explicit, and define fallback policy | Same markdown math yields equivalent visual output across supported platforms |
| P1 | Concurrency guarantees are implicit | `TextKit` objects are class-based and reused; future parallel solve calls may race | Document thread model and enforce isolation boundary (queue/actor or per-task instances) | No shared mutable `TextKit` state accessed concurrently |
| P1 | (Improved) Documentation drift (coverage + feature docs) | Coverage docs now updated to reflect 165 tests | Continue updating after each test/feature change | Docs reflect current code and test status |
| P2 | (Partially resolved) Platform test matrix is uneven | macOS UI now tested (8 tests); iOS DataSource still untested | Add iOS DataSource tests and CI matrix notes | Critical rendering paths covered on both target platforms |
| P2 | Performance targets lack reproducible benchmark baseline | Hard to detect regressions over time | Add reproducible benchmark scenario + output format using `PerformanceProfiler` | Baseline numbers versioned in docs and comparable per commit |

## Recommended Execution Order

1. Resolve table strategy mismatch first (P0) to get CI and docs back in sync.
2. Add public API facade (P0) before further feature growth.
3. Lock down thread-safety boundaries and math parity (P1).
4. Refresh docs and platform test matrix (P1/P2).
5. Add repeatable benchmark baseline (P2).

## Suggested Work Batches

### Batch A (Immediate, 1-2 commits)

- Align table implementation/tests/docs to one strategy.
- Ensure `swift test` is fully green.

### Batch B (Short term)

- Introduce public API facade in `MarkdownKit.swift`.
- Document thread-safety contract for layout and async rendering components.

### Batch C (Stabilization)

- Cross-platform math rendering parity updates.
- Documentation refresh and benchmark baseline publication.
