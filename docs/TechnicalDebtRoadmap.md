# Technical Debt Roadmap (as of 2026-03-04)

## Current Health Snapshot

- `swift test`: **218 tests executed, 0 failures** (latest local run).
- Snapshot drift issue on macOS has been stabilized by fixing test appearance constraints.
- Mermaid adapter/API mismatch (`MermaidHTMLBuilder.makeHTML`) has been repaired.
- Public API facade (`MarkdownKitEngine`) is already available and documented in README.
- `SplashHighlighter.highlight(_:language:)` now respects explicit language input (non-Swift -> plain fallback).
- Concurrency boundaries are documented in `docs/ConcurrencyContract.md`.

## Prioritized Debt List

| Priority | Debt Item | Current Impact | Recommended Action | Done Criteria |
|---|---|---|---|---|
| P2 | MathJax unsupported formulas (e.g. `\\binom`) still produce one warning per unique error | Heavy logs can still include warning output, though no longer repeated spam | Keep suppression policy and consider route-to-logger/metrics instead of stdout | Warning signal remains useful without polluting CI output |
| P2 | Concurrency model still relies on discipline around `@unchecked Sendable` boundaries | Future refactors can accidentally cross isolation assumptions | Add focused stress tests for parser/layout/render interleaving and tighten annotations over time | Key pipelines are contract-tested under concurrent access |
| P2 | Syntax highlighting is Swift-only | Non-Swift fenced code falls back to plain style; no multi-language tokenization yet | Evaluate adding additional grammars/highlighters or make fallback strategy explicit in public docs | Language support matrix is explicit and test-covered |
| P2 | iOS table rendering still uses text/tab emulation while macOS uses native table blocks | Cross-platform visual parity gap remains for complex tables | Continue improving iOS readability and clarify parity boundary in docs/tests | Narrow-width and alignment behavior stay stable; constraints documented |
| P2 | Verification cost for full suite remains high (benchmarks in `swift test`) | Slower local feedback loop | Keep fast-path verification as default and separate heavy benchmark path | Team default command runs quickly; heavy path is explicit |
| P2 | Documentation drift can reappear as test counts/features evolve | Mismatch between docs and code causes onboarding confusion | Automate or semi-automate doc refresh for coverage/status docs | Coverage/status docs generated from repeatable commands/scripts |

## Recommended Execution Order

1. Keep improving iOS table parity within current architecture constraints.
2. Harden concurrent stress coverage around layout/render boundaries.
3. Decide multi-language highlighting strategy (keep plain fallback vs add grammars).
4. Continue reducing full-suite feedback cost.
5. Continue hardening documentation refresh automation.

## Suggested Work Batches

### Batch A (Immediate)

- Math warning throttling + tests.
- Verification workflow split (fast vs heavy) and command docs.

### Batch B (Short Term)

- Concurrency stress coverage for documented contract.
- Syntax highlighting strategy decision for non-Swift languages.

### Batch C (Stabilization)

- iOS table parity incremental improvements.
- Continue reducing manual documentation maintenance.
