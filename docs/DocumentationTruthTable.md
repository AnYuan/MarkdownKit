# Documentation Truth Table (2026-07-16)

本表用于快速判断当前仓库文档的“可依赖程度”，并给出最小修复动作。

## 判定标准

- A (高可信): 与当前代码和脚本基本一致，可作为日常执行依据
- B (部分过时): 主体正确，但包含已漂移的状态数据或结论
- C (明显过时): 关键判断已被代码/测试推翻，需优先修订

## 文档真相表

| 文档 | 主要用途 | 可信度 | 主要问题/观察 | 建议动作 |
| --- | --- | --- | --- | --- |
| `README.md` | 项目入口与快速使用 | A | API 用法与 `MarkdownKitEngine`、`scripts/verify_all.sh` 一致 | 作为 onboarding 首读文档，保持精简 |
| `docs/PRD.md` | 产品目标与验收边界 | A | 目标定义完整，仍可作为长期北极星 | 每次新增语法特性时同步更新 §3 和 §7 |
| `docs/PLAN.md` | 实施节奏与验证策略 | A | 自动化验证主线清晰，和脚本入口一致 | 继续用于阶段性执行跟踪 |
| `docs/CodebaseKnowledge.md` | 当前实现快照与架构索引 | B | 测试发现数由严格 freshness gate 核对；其余时间快照数据仍可能漂移 | 保留为快照文档；按月刷新非门禁统计字段 |
| `docs/FeatureMatrix.md` | 功能状态矩阵 | A | 与测试映射关系清楚，可用于评审和回归 | 新增功能时同步补齐对应测试链接 |
| `docs/ImplementationChecklist.md` | 原子任务完成记录 | A | 当前波次已完成，闭环明确 | 可保留归档；新波次另开新 checklist |
| `docs/BENCHMARK_BASELINE.md` | 性能基线与回归阈值参考 | A | 由 `benchmark_baseline.json` 通过渲染脚本生成，JSON 是单一事实源 | 修改 JSON 后重新生成，并运行渲染器 `--check` |
| `docs/TestCoverage.md` | 时间戳化测试清单与执行快照 | B | 由脚本生成且具有归档性质；`swift test list` 计数受严格门禁约束，执行结论仅在提供日志时有效 | 按需重新生成；不得把“未提供执行日志”写成通过 |
| `scripts/check_doc_freshness.sh` | CI 文档新鲜度门禁 | A | Bash 3.2 兼容的严格只读门禁；校验测试列表格式/计数和 benchmark 生成文档 | 已接入 CI（macOS `verify` job 的独立步骤）；任何解析、计数或生成物漂移均失败 |
| `docs/TechnicalDebtRoadmap.md` | 技术债排序 | B | 仍写“Public API facade is empty”，但 `MarkdownKitEngine` 已实现 | 删除已解决项，补充仍未解决项（并发隔离、数学一致性等） |
| `docs/evaluation_report.md` | 生产级风险评估 | B | 已修正旧结论并同步当前状态，后续需随风险变化滚动更新 | 每轮稳定性改动后刷新“主要风险”章节 |
| `docs/Layout.md` | 布局引擎概念说明 | B | 架构描述正确，但偏概念，缺少实现细节与约束 | 增加“现状实现 vs 目标愿景”分节 |
| `docs/Virtualization.md` | 虚拟化渲染思路 | B | 概念性强，缺少与现有组件对应关系 | 补一节“代码入口索引” |
| `docs/AST.md` | AST 设计概览 | B | 内容较短，覆盖节点不全 | 扩展为节点族谱和插件插入点索引 |
| `docs/Texture.md` | 架构借鉴背景 | B | 更像设计理念文档，不是当前实现事实文档 | 标注“设计参考”性质，避免与实现文档混淆 |
| `docs/RenderingPipelineSequence.md` | 渲染时序图 | A | 时序与现有 pipeline 基本一致 | 保持为架构演示文档 |
| `docs/ExtendedFeatures.md` | 扩展特性说明 | A | 大方向与现状一致 | 每个特性补上对应测试文件名 |
| `Sources/MarkdownKit/MarkdownKit.docc/MarkdownKit.md` | 对外 API 文档首页 | A | 入门可用，核心符号可达 | 可追加 `MarkdownKitEngine` 一键入口示例 |
| `Sources/MarkdownKit/MarkdownKit.docc/Tutorials/GettingStarted.md` | DocC 入门教程 | A | 流程正确，可执行 | 加一段“推荐默认插件链”说明 |
| `tasks/todo.md` | 历史执行清单 | B | 基本为已完成历史，容易和 `docs/PLAN.md` 重复 | 保留归档，新增任务改用新的 todo 文件 |
| `GEMINI.md` | 团队流程/执行规范 | B | 更多是流程原则，不是项目事实状态 | 与项目事实文档分层，避免混作状态来源 |

## 证据锚点（用于核对）

- API facade 已存在: `Sources/MarkdownKit/MarkdownKit.swift`
- 当前测试文件数量: `find Tests/MarkdownKitTests -maxdepth 1 -type f -name '*.swift' | wc -l`（当前为 69）
- 当前可发现测试数: `swift test list`（405）；`TestCoverage` 本次未提供全量执行日志: `docs/TestCoverage.md`
- Benchmark 文档事实源: `Tests/MarkdownKitTests/Fixtures/benchmark_baseline.json`；生成一致性检查: `python3 scripts/render_benchmark_baseline.py --check`
- 严格文档新鲜度门禁: `bash scripts/check_doc_freshness.sh`
- `evaluation_report` 已改为当前风险基线: `docs/evaluation_report.md`
- `TechnicalDebtRoadmap` 仍声明 facade 为空: `docs/TechnicalDebtRoadmap.md`

## 推荐执行顺序（文档清理）

1. 先修 B 级“状态漂移”文档: `docs/TechnicalDebtRoadmap.md`, `docs/CodebaseKnowledge.md`
2. 再做结构优化: `docs/Layout.md`, `docs/Virtualization.md`, `docs/AST.md`
