# MarkdownKit Feature-Status Matrix

This document traces the advanced parsing and layout features (defined in Phase 6 / PRD §7) directly to their automated test coverage cases, providing a quick dashboard of completion status.

## P0: Core Markdown Rendering Parity
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| CommonMark Compliance | ✅ | `CommonMarkSpecTests.swift` |
| Native `NSTextTable` Rendering (macOS) / Tab-stop emulation (iOS) | ✅ | `SnapshotTests.testTableRendering`, `iOSTableLayoutTests` |
| GitHub Table Styling & Alignment | ✅ | `ParserLinkListTableTests.testTableWithColumnAlignments` |
| Fenced Math Blocks (````math``) | ✅ | `SnapshotTests.testMathRendering` |
| Inline Math (`$...$`) | ✅ | `MathExtractionPluginTests.testMathPluginReplacesBlocksAndInlineNodes` |
| Code Block Badges | ✅ | `SnapshotTests.testCodeBlockRendering` |

## P1: Advanced Formatting Features
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| `<details>/<summary>` Collapsible Blocks | ✅ | `DetailsExtractionPluginTests.swift`, `MarkdownRenderCoordinatorTests.testDebouncedDarkToggleUsesLatestConfigurationWithoutReparse` |
| Diagram Fenced Languages (`mermaid`, etc) | ✅ | `DiagramExtractionPluginTests.swift` |
| GitHub Autolinks (`@mentions`, `#issues`) | ✅ | `GitHubAutolinkPluginTests.swift` |
| Interactive Task Lists | ✅ | `SnapshotTests.testTasklistRendering` |

## P2: Host-App Integration Boundaries
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| `MarkdownAutolinkResolver` destination hook (`@mention`, reference, commit) | ✅ | `GitHubAutolinkPluginTests.swift`, `MarkdownKitTests.swift` |
| Attachment upload workflow hooks | Host-owned (no renderer hook) | N/A |
| Semantic issue-keyword workflow hooks | Host-owned (no renderer hook) | N/A |
| Custom action/permalink workflow hooks | Host-owned (no renderer hook) | N/A |

## Phase 7: Production Readiness (Security & Robustness)
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| URL Scheme Allow-listing | ✅ | `URLSanitizerTests.swift` |
| Per-Parser Input Limit and Typed Rejection | ✅ | `ParserResourceLimitTests.swift` |
| Native-AST Mapping Recursion Limit (`MarkdownParser.ResourceLimits.maximumNestingDepth`, default 50 — bounds only `MarkdownKitVisitor`'s mapping recursion, not `swift-markdown` parsing or layout depth) | ✅ | `DepthLimitTests.swift` |
| Fuzzing & Malformed Document Testing | ✅ | `FuzzTests.swift` |
