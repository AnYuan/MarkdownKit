# MarkdownKit 测试覆盖与执行快照

> 最近更新: 2026-07-17
> 生成方式: `python3 scripts/generate_test_coverage_report.py [--run-tests|--from-log <path>]`
> 生成时间: 2026-07-17 09:44:08

## 1. 总览

| 指标 | 当前值 | 说明 |
| --- | ---: | --- |
| 源码文件数 (`Sources/MarkdownKit/*.swift`) | 79 | 不含 Demo target |
| 测试文件数 (`Tests/MarkdownKitTests/*.swift`) | 67 | 含基准/夹具/辅助文件 |
| 含 `test*` 方法的测试文件 | 59 | 静态扫描结果 |
| 静态扫描 `test*` 方法总数 | 455 | 受编译条件影响，可能高于可执行测试数 |
| 可发现测试数 (`swift test list`) | 377 | 当前平台可执行测试 |
| 全量执行结果 (`swift test`) | 未提供 | 未执行或未提供日志 |

## 2. 本次执行状态

- 未提供 `swift test` 执行结果；可用 `--run-tests` 或 `--from-log` 补充。

## 3. 测试文件明细

| 文件 | `test*` 方法数 |
| --- | ---: |
| `ASTPluginTests.swift` | 13 |
| `ASTTransformTests.swift` | 6 |
| `ArithmeticTextCalculatorTests.swift` | 25 |
| `AsyncCodeViewCopyTests.swift` | 7 |
| `AsyncImageViewLoadingTests.swift` | 6 |
| `AsyncTextViewInteractionTests.swift` | 5 |
| `AsyncTextViewRenderTests.swift` | 6 |
| `AttributedStringBuilderEquivalenceTests.swift` | 9 |
| `BenchmarkBaseline.swift` | 0 |
| `BenchmarkCacheTests.swift` | 2 |
| `BenchmarkFixtures.swift` | 0 |
| `BenchmarkHarness.swift` | 0 |
| `BenchmarkNodeTypeTests.swift` | 7 |
| `BenchmarkRegressionGuard.swift` | 0 |
| `BenchmarkReportFormatter.swift` | 0 |
| `BenchmarkTieredFixtures.swift` | 0 |
| `CommonMarkSpecTests.swift` | 2 |
| `ConcurrencyStressTests.swift` | 4 |
| `CrossPlatformLayoutTests.swift` | 10 |
| `DepthLimitTests.swift` | 3 |
| `DetailsExtractionPluginTests.swift` | 4 |
| `DiagramExtractionPluginTests.swift` | 3 |
| `DiagramLayoutTests.swift` | 8 |
| `DiagramSnapshotTests.swift` | 1 |
| `EdgeCaseTests.swift` | 13 |
| `FuzzTests.swift` | 1 |
| `GitHubAutolinkPluginTests.swift` | 8 |
| `HighlighterAndProfilerTests.swift` | 12 |
| `InlineFormattingLayoutTests.swift` | 28 |
| `IntegrationPipelineTests.swift` | 10 |
| `LayoutCacheEdgeCaseTests.swift` | 12 |
| `LayoutSolverExtendedTests.swift` | 16 |
| `LayoutTests.swift` | 5 |
| `MacOSUIComponentsTests.swift` | 10 |
| `MarkdownKitBenchmarkTests.swift` | 4 |
| `MarkdownKitTests.swift` | 5 |
| `MathCacheTests.swift` | 3 |
| `MathExtractionPluginTests.swift` | 16 |
| `MathSVGPreprocessorTests.swift` | 9 |
| `MathWarningSuppressorTests.swift` | 3 |
| `MermaidDiagramAdapterTests.swift` | 3 |
| `NodeModelTests.swift` | 18 |
| `ParserInlineFormattingTests.swift` | 12 |
| `ParserLinkListTableTests.swift` | 11 |
| `ParserResourceLimitTests.swift` | 16 |
| `PerformanceBaselineContractTests.swift` | 10 |
| `PerformanceProfilerTests.swift` | 2 |
| `PlatformAccessibilityTests.swift` | 5 |
| `SendableTests.swift` | 2 |
| `SnapshotTestHelper.swift` | 0 |
| `SnapshotTests.swift` | 4 |
| `StableNodeIdentityTests.swift` | 4 |
| `SyntaxMatrixTests.swift` | 1 |
| `TableOfContentsBuilderTests.swift` | 4 |
| `TestHelper.swift` | 0 |
| `TextKitCalculatorTests.swift` | 4 |
| `TextKitHitTesterTests.swift` | 6 |
| `ThemeAndTokenTests.swift` | 10 |
| `ThemeCustomizationTests.swift` | 15 |
| `UIComponentsPlatformTests.swift` | 11 |
| `UIComponentsTests.swift` | 2 |
| `URLSanitizerTests.swift` | 8 |
| `VirtualizationTests.swift` | 1 |
| `iOSAccessibilityTests.swift` | 8 |
| `iOSSnapshotTests.swift` | 6 |
| `iOSTableLayoutTests.swift` | 12 |
| `iOSThemeDelegateTests.swift` | 4 |

## 4. 辅助/夹具文件（无 `test*` 方法）

- `BenchmarkBaseline.swift`
- `BenchmarkFixtures.swift`
- `BenchmarkHarness.swift`
- `BenchmarkRegressionGuard.swift`
- `BenchmarkReportFormatter.swift`
- `BenchmarkTieredFixtures.swift`
- `SnapshotTestHelper.swift`
- `TestHelper.swift`

## 5. 建议

1. 日常开发优先使用快速验证入口，减少完整 benchmark 负担。
2. 每次变更后用该脚本刷新覆盖快照，避免手工统计漂移。
