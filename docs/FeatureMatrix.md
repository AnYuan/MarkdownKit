# MarkdownKit Feature-Status Matrix

This document traces the advanced parsing and layout features (defined in Phase 6 / PRD §7) directly to their automated test coverage cases, providing a quick dashboard of completion status.

## P0: Core Markdown Rendering Parity
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| CommonMark Compliance | ✅ | `CommonMarkSpecTests.swift` |
| Native `NSTextTable` Rendering | ✅ | `SnapshotTests.testTableRendering` |
| GitHub Table Styling & Alignment | ✅ | `ParserLinkListTableTests.testTableParsingWithAlignments` |
| Fenced Math Blocks (````math``) | ✅ | `SnapshotTests.testMathRendering` |
| Inline Math (`$...$`) | ✅ | `MathExtractionPluginTests.testMathPluginReplacesBlocksAndInlineNodes` |
| Code Block Badges | ✅ | `SnapshotTests.testCodeBlockRendering` |

## P1: Advanced Formatting Features
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| `<details>/<summary>` Collapsible Blocks | ✅ | `DetailsExtractionPluginTests.testMatchesSummaryAndContent` |
| Diagram Fenced Languages (`mermaid`, etc) | ✅ | `DiagramExtractionPluginTests.swift` |
| GitHub Autolinks (`@mentions`, `#issues`) | ✅ | `GitHubAutolinkPluginTests.swift` |
| Interactive Task Lists | ✅ | `SnapshotTests.testTasklistRendering` |

## P2: Host-App Integration Boundaries
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| `MarkdownContextDelegate` Extensibility | ✅ | N/A (Protocol Definition) |
| Async Attachment Workflow Hooks | ✅ | N/A (Protocol Definition) |
| Semantic Issue Keywords Hooks | ✅ | N/A (Protocol Definition) |
| Custom Action/Permalink Hooks | ✅ | N/A (Protocol Definition) |

## Phase 7: Production Readiness (Security & Robustness)
| Feature | Status | Covered By Unit/Snapshot Tests |
| :--- | :---: | :--- |
| URL Scheme Allow-listing | ✅ | `URLSanitizerTests.swift` |
| Recursive Depth Limiting (StackOverflow) | ✅ | `DepthLimitTests.swift` |
| Fuzzing & Malformed Document Testing | ✅ | `FuzzTests.swift` |
