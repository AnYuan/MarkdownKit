# MarkdownKit 生产级别评估报告（更新版）

> 更新日期: 2026-07-17
> 说明: 本报告替代旧版结论；旧版中“缺 URL 净化 / 缺深度限制 / 缺 Fuzz / 缺快照测试”的判断已不再成立。

## 1. 结论摘要

当前仓库已具备生产级渲染引擎的核心防护与测试骨架：
- 安全防护已落地（URL 协议净化、危险 scheme 过滤、深度限制）。
- 稳健性测试已落地（Fuzz、边界、CommonMark 大样本解析）。
- 快照测试框架已接入并稳定运行（快照失败已收敛）。

整体状态建议评定为: **可用于主线开发（需持续控制快照环境漂移）**。

## 2. 关键事实（已核对）

### 2.1 安全性

- `LinkNode` / `ImageNode` 在初始化时经过 `URLSanitizer`。
- `URLSanitizer` 对 `javascript:`, `vbscript:`, `data:text/html` 等危险前缀有显式拦截。
- 可配置 allow-list scheme，默认策略为白名单放行。

### 2.2 深度与鲁棒性

- `MarkdownParser` 通过 `ResourceLimits`（默认 `maximumInputBytes` 1,048,576 UTF-8 字节、`maximumNestingDepth` 50）限制资源占用；`maximumNestingDepth` 仅约束 `MarkdownKitVisitor` 把已解析的 `swift-markdown` 树映射为原生 AST 时保留的容器嵌套层数。根 `Document` 不计入，达到边界时保留容器但省略其后代；这并非 `swift-markdown` 前端解析器或布局阶段的深度限制。
- 类型化的 `parseOutcome(_:)` 会区分 `.rejected`（输入超过 `maximumInputBytes`）与 `.parsed`（可能带有深度截断诊断），且不写日志；历史兼容方法 `parse(_:) -> DocumentNode` 是有损的便捷封装，会记录诊断日志，并将拒绝态折叠为历史空文档、深度截断折叠为部分文档。
- `DepthLimitTests`、`FuzzTests` 已存在并可执行。
- `CommonMarkSpecTests` 包含大样本解析验证（652 fixture）。

### 2.3 快照与视觉回归

- 快照框架已接入 (`SnapshotTesting`)。
- 相关测试文件存在：`SnapshotTests.swift`、`iOSSnapshotTests.swift`、`DiagramSnapshotTests.swift`。
- `SnapshotTests` 中历史 4 项失败已修复（通过固定 `NSAppearance(.aqua)` 消除动态外观漂移）。
- 当前测试数量与执行结果由 `scripts/verify_fast.sh`、`scripts/verify_snapshots.sh`
  和 `docs/TestCoverage.md` 分别记录；本评估报告不再复制易漂移的汇总数字。

### 2.4 API 与工程化

- 公共入口 facade 已存在：`MarkdownKitEngine`（默认插件链、构造 parser/solver、一键 layout）。
- Mermaid 脚本采用本地资源打包（`Package.swift` 声明 `Resources/mermaid.min.js`），不再依赖线上 CDN 作为唯一路径。

## 3. 当前主要风险

### P1: 快照环境漂移复发风险

现象:
- 快照测试依赖运行时外观/字体/渲染环境，历史上出现过 4 项快照漂移失败。

影响:
- 如果环境约束放松，可能再次触发视觉基线误报。

建议:
1. 保持 macOS 快照测试固定外观（`NSAppearance(.aqua)`）与固定尺寸。
2. 在新增快照用例时复用同一初始化模板，避免测试之间策略不一致。

### P1: MathJax 警告噪音（`\binom`）

现象:
- 基准与测试日志会出现重复 `Undefined control sequence \binom`。

影响:
- 日志噪音高，影响定位真实失败。

建议:
1. 统一定义 math fallback 级别（警告降级/聚合去重）。
2. 增加单测覆盖该类公式的期望行为（渲染成功或一致降级）。

### P2: 全量测试耗时偏高

现象:
- `swift test` 默认包含重基准，耗时约 80s 量级（取决于机器）。

影响:
- 本地迭代反馈慢。

建议:
1. 默认执行 `scripts/verify_all.sh` 的快速分组。
2. 将重基准放入可选或 nightly 流程。

## 4. 近期建议执行顺序

1. 处理 MathJax `\binom` 的日志与降级策略。
2. 调整 CI 流水线分层（快速回归 vs 重基准）。
3. 将快照固定外观策略提炼为测试工具函数，减少后续漂移风险。

## 5. 与旧版报告的关系

旧版 `evaluation_report.md` 的以下判断已过期:
- “缺 URL 净化”
- “缺深度限制”
- “缺 Fuzz”
- “缺 Snapshot 测试”

本文件已按当前代码和测试状态完成修正，可作为新的评估基线。
