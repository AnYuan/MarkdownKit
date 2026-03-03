# MarkdownKit 生产级别评估报告（更新版）

> 更新日期: 2026-03-04
> 说明: 本报告替代旧版结论；旧版中“缺 URL 净化 / 缺深度限制 / 缺 Fuzz / 缺快照测试”的判断已不再成立。

## 1. 结论摘要

当前仓库已具备生产级渲染引擎的核心防护与测试骨架：
- 安全防护已落地（URL 协议净化、危险 scheme 过滤、深度限制）。
- 稳健性测试已落地（Fuzz、边界、CommonMark 大样本解析）。
- 快照测试框架已接入并在运行中（但当前存在 4 个快照差异失败）。

整体状态建议评定为: **可用但需收敛快照基线**。

## 2. 关键事实（已核对）

### 2.1 安全性

- `LinkNode` / `ImageNode` 在初始化时经过 `URLSanitizer`。
- `URLSanitizer` 对 `javascript:`, `vbscript:`, `data:text/html` 等危险前缀有显式拦截。
- 可配置 allow-list scheme，默认策略为白名单放行。

### 2.2 深度与鲁棒性

- `MarkdownKitVisitor` 存在 `maxDepth`（默认 50）限制。
- `DepthLimitTests`、`FuzzTests` 已存在并可执行。
- `CommonMarkSpecTests` 包含大样本解析验证（652 fixture）。

### 2.3 快照与视觉回归

- 快照框架已接入 (`SnapshotTesting`)。
- 相关测试文件存在：`SnapshotTests.swift`、`iOSSnapshotTests.swift`、`DiagramSnapshotTests.swift`。
- 2026-03-04 的 `swift test` 结果中，出现 4 个快照不一致失败（同属 `SnapshotTests`）。

### 2.4 API 与工程化

- 公共入口 facade 已存在：`MarkdownKitEngine`（默认插件链、构造 parser/solver、一键 layout）。
- Mermaid 脚本采用本地资源打包（`Package.swift` 声明 `Resources/mermaid.min.js`），不再依赖线上 CDN 作为唯一路径。

## 3. 当前主要风险

### P0: 快照基线漂移导致 CI 不稳定

现象:
- `SnapshotTests.testCodeBlockRendering`
- `SnapshotTests.testMathRendering`
- `SnapshotTests.testTableRendering`
- `SnapshotTests.testTasklistRendering`

影响:
- 视觉回归门禁失效（无法区分“预期改动”与“真实回归”）。

建议:
1. 先确认最近渲染改动是否预期。
2. 预期改动则更新参考快照；非预期则先修复渲染再更新快照。

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
- `swift test` 默认包含重基准，耗时约 90s 量级（取决于机器）。

影响:
- 本地迭代反馈慢。

建议:
1. 默认执行 `scripts/verify_all.sh` 的快速分组。
2. 将重基准放入可选或 nightly 流程。

## 4. 近期建议执行顺序

1. 修复/更新 4 个快照失败（先做）。
2. 处理 MathJax `\binom` 的日志与降级策略。
3. 调整 CI 流水线分层（快速回归 vs 重基准）。

## 5. 与旧版报告的关系

旧版 `evaluation_report.md` 的以下判断已过期:
- “缺 URL 净化”
- “缺深度限制”
- “缺 Fuzz”
- “缺 Snapshot 测试”

本文件已按当前代码和测试状态完成修正，可作为新的评估基线。

