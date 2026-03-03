# MarkdownKit Next Implementation Checklist (Atomic)

This checklist is the concrete execution slice after `docs/CodebaseKnowledge.md`.
It focuses on closing known gaps with low-risk, test-first, atomic commits.

## Execution Rules

1. Each item should land as one atomic commit.
2. Every item must include at least one positive-path and one fallback-path test.
3. Prefer deterministic local fixtures; avoid external network dependency in default tests.
4. Do not start a later item before its prerequisite item is merged.

## [x] C1. Fix Layout Cache Key Consistency (P0)

- Objective: make `LayoutCache` hash/equality semantics consistent for width matching.
- Problem:
  - `CacheKey.hash` uses full `width`
  - `CacheKey.isEqual` uses tolerance (`abs(width diff) < 0.1`)
  - This can produce unstable cache hit behavior near width boundaries.
- Files:
  - `Sources/MarkdownKit/Layout/LayoutCache.swift`
  - `Tests/MarkdownKitTests/LayoutCacheEdgeCaseTests.swift`
- Change:
  - Normalize width before both hashing and equality (single source of truth).
  - Remove mixed exact-vs-tolerant behavior.
- DoD:
  - Existing cache tests pass.
  - Add regression test for near-equal widths proving deterministic behavior.
- Verify:
  - `swift test --filter LayoutCacheEdgeCaseTests`

## [x] C2. Inline Code Visual Upgrade (P0)

- Objective: make inline code visually distinct and stable across light/dark appearance.
- Problem:
  - Inline code currently has background but weak contrast in some contexts.
  - No dedicated token for inline-code styling in `Theme`.
- Files:
  - `Sources/MarkdownKit/Theme/Theme.swift`
  - `Sources/MarkdownKit/Layout/LayoutSolver.swift`
  - `Tests/MarkdownKitTests/InlineFormattingLayoutTests.swift`
  - `Tests/MarkdownKitTests/ThemeAndTokenTests.swift`
- Change:
  - Add explicit inline-code color token(s) to `Theme`.
  - Apply paddings/rounded-background-compatible attributes where platform allows.
  - Keep fallback safe when custom token is absent.
- DoD:
  - Inline code clearly differs from body text in both themes.
  - Tests assert presence of foreground/background and contrast-safe defaults.
- Verify:
  - `swift test --filter "InlineFormattingLayoutTests|ThemeAndTokenTests"`

## [x] C3. iOS Table Rendering Readability Hardening (P0)

- Objective: ensure table text does not collapse vertically and remains readable at narrow widths.
- Problem:
  - iOS path is tab-stop emulation; long cells can degrade readability.
- Files:
  - `Sources/MarkdownKit/Layout/LayoutSolver.swift`
  - `Tests/MarkdownKitTests/iOSTableLayoutTests.swift`
  - `Tests/MarkdownKitTests/CrossPlatformLayoutTests.swift`
  - `Tests/MarkdownKitTests/iOSSnapshotTests.swift` (if snapshot needs refresh)
- Change:
  - Tune paragraph style/tab-stop spacing and wrap strategy for narrow widths.
  - Keep the 8pt horizontal inset behavior.
- DoD:
  - No column text collapse in constrained widths.
  - New regression test reproduces prior broken case and passes.
- Verify:
  - `swift test --filter "iOSTableLayoutTests|CrossPlatformLayoutTests|iOSSnapshotTests"`

## [x] C4. Mermaid Rendering Sandbox Safety (P0)

- Objective: avoid runtime fragility caused by remote Mermaid CDN and sandbox restrictions.
- Problem:
  - Current `MermaidDiagramAdapter` loads Mermaid from CDN in `WKWebView`.
  - In restricted runtime, `WebContent` can fail/crash and diagrams degrade unpredictably.
- Files:
  - `Sources/MarkdownKit/Plugins/MermaidDiagramAdapter.swift`
  - `Package.swift` (resource bundling if local JS is added)
  - `Tests/MarkdownKitTests/DiagramLayoutTests.swift`
- Change:
  - Prefer local Mermaid script asset (bundled resource) over network CDN.
  - Add explicit timeout/failure fallback path and bounded snapshot rect.
- DoD:
  - Adapter does not require network for baseline rendering.
  - On failure, solver cleanly falls back to code-block rendering.
- Verify:
  - `swift test --filter DiagramLayoutTests`

## [x] C5. Image Loading Reliability and Fallback Coverage (P1)

- Objective: make image behavior predictable for remote/local/unavailable sources.
- Problem:
  - Restricted environments can fail remote fetch; fallback coverage should be explicit.
- Files:
  - `Sources/MarkdownKit/Layout/LayoutSolver.swift`
  - `Sources/MarkdownKit/UI/Components/AsyncImageView.swift`
  - `Tests/MarkdownKitTests/AsyncImageViewLoadingTests.swift`
  - `Tests/MarkdownKitTests/InlineFormattingLayoutTests.swift`
  - `Tests/MarkdownKitTests/SyntaxMatrixTests.swift`
- Change:
  - Strengthen source resolution and failure handling paths.
  - Ensure fallback text behavior is deterministic and testable.
- DoD:
  - Local fixture image always renders.
  - Missing/blocked remote image always falls back to `[alt]`.
- Verify:
  - `swift test --filter "AsyncImageViewLoadingTests|InlineFormattingLayoutTests|SyntaxMatrixTests"`

## [x] C6. Public API Surface Cleanup (P1)

- Objective: replace placeholder `MarkdownKit.swift` with minimal, stable entry APIs.
- Problem:
  - `Sources/MarkdownKit/MarkdownKit.swift` is currently placeholder comments only.
- Files:
  - `Sources/MarkdownKit/MarkdownKit.swift`
  - `README.md`
  - `Sources/MarkdownKit/MarkdownKit.docc/*` (if symbols referenced)
  - `Tests/MarkdownKitTests/MarkdownKitTests.swift`
- Change:
  - Add convenient factory APIs for:
    - default parser pipeline
    - default layout solver
    - recommended plugin chain
- DoD:
  - Users can start with one import + one helper call path.
  - README quick-start code reflects actual public API.
- Verify:
  - `swift test --filter MarkdownKitTests`

## [x] C7. CommonMark Semantic Validation Extension (P1)

- Objective: go beyond crash resilience and validate selected semantic expectations.
- Problem:
  - `CommonMarkSpecTests` currently guarantees parse success only.
- Files:
  - `Tests/MarkdownKitTests/CommonMarkSpecTests.swift`
  - `Tests/MarkdownKitTests/ParserInlineFormattingTests.swift`
  - `Tests/MarkdownKitTests/ParserLinkListTableTests.swift`
- Change:
  - Add a curated semantic subset (golden assertions) from spec fixtures.
  - Keep full 652-case test for non-crash gate.
- DoD:
  - At least one semantic assertion set per major syntax family.
  - Failures include fixture id/line section diagnostics.
- Verify:
  - `swift test --filter "CommonMarkSpecTests|ParserInlineFormattingTests|ParserLinkListTableTests"`

## [x] C8. One-Command Verification Entry (P1)

- Objective: provide one deterministic automation entrypoint for daily checks.
- Problem:
  - Verification exists but is spread across multiple commands.
- Files:
  - `scripts/verify_all.sh` (new)
  - `README.md`
  - `docs/PLAN.md`
- Change:
  - Add a script that runs:
    - syntax matrix
    - critical plugin suites
    - layout regressions
    - security suites
  - Keep benchmark suites optional flag (because heavy).
- DoD:
  - `./scripts/verify_all.sh` exits non-zero on failure and prints suite boundaries.
- Verify:
  - `bash scripts/verify_all.sh`

## Suggested Order

1. C1 (cache correctness baseline)
2. C3 (iOS table readability)
3. C4 (mermaid sandbox safety)
4. C5 (image reliability)
5. C2 (inline code visual polish)
6. C6 (public API cleanup)
7. C7 (semantic CommonMark extension)
8. C8 (one-command verification wrapper)

## Merge Gate for This Wave

Minimum required before declaring this wave complete:

1. `swift test --filter SyntaxMatrixTests`
2. `swift test --filter "DetailsExtractionPluginTests|DiagramExtractionPluginTests|MathExtractionPluginTests|GitHubAutolinkPluginTests"`
3. `swift test --filter "LayoutSolverExtendedTests|InlineFormattingLayoutTests|CrossPlatformLayoutTests|iOSTableLayoutTests"`
4. `swift test --filter "URLSanitizerTests|DepthLimitTests|FuzzTests"`
