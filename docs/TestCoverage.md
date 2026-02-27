# MyMarkdown 单元测试覆盖率报告

> 最近更新: 2026-02-27
> 测试框架: XCTest
> Swift 版本: 6.2+

---

## 总览 (最新)

| 指标 | 之前 | 现在 |
| ------ | ------ | ------ |
| 测试文件 | 3 | 11 (+8) |
| 测试方法 | 5 | 76 (+71) |
| 有测试覆盖的源文件 | 5 / 36 (14%) | 30 / 36 (83%) |
| 有测试覆盖的模块 | 4 / 9 (44%) | 9 / 9 (100%) |
| 预估行覆盖率 | ~15-20% | ~75-80% |
| 预估分支覆盖率 | ~8-12% | ~60-65% |

---

## 各模块覆盖率

| 模块 | 源文件数 | 覆盖状态 | 预估覆盖率 |
|------|---------|---------|-----------|
| Parsing (解析) | 3 | 部分覆盖 | ~40% |
| Nodes (AST 节点) | 13 | 少量覆盖 | ~15% |
| Layout (布局引擎) | 6 | 部分覆盖 | ~25% |
| Theme (主题) | 1 | 无覆盖 | 0% |
| Highlighter (语法高亮) | 1 | 部分覆盖 | ~30% |
| Math (数学渲染) | 1 | 少量覆盖 | ~20% |
| UI/Components (异步组件) | 3 | 极少覆盖 | ~5% |
| UI/CollectionView (虚拟化) | 4 | 极少覆盖 | ~10% |
| Utils (工具) | 1 | 部分覆盖 | ~40% |

---

## 已有测试明细

### MyMarkdownTests.swift (2 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testBasicCommonMarkParsing()` | MarkdownParser.parse() → DocumentNode 子节点数量、HeaderNode level、ParagraphNode 文本内容 |
| `testCodeAndImageGFMParsing()` | CodeBlockNode language + code 属性、ImageNode source/altText/title 属性 |

### LayoutTests.swift (3 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testBackgroundLayoutSizingAndCaching()` | LayoutSolver.solve() 异步布局、100pt 宽度约束下的尺寸计算、LayoutCache 缓存命中与 clear() |
| `testSyntaxHighlighting()` | SplashHighlighter 对 Swift 代码生成多色 NSAttributedString（验证 attribute runs > 1） |
| `testMathJaxBackgroundRendering()` | MathRenderer 异步渲染 `$E=mc^2$`、验证 NSTextAttachment 嵌入（仅 UIKit 平台） |

### UIComponentsTests.swift (1 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testVirtualizationPurging()` | MarkdownCollectionViewCell.configure() 挂载 AsyncTextView/AsyncCodeView、prepareForReuse() 清理子视图（仅 UIKit 平台） |

---

## 各源文件覆盖详情

### Parsing 模块

| 文件 | 已覆盖 | 未覆盖 |
|------|--------|--------|
| MarkdownParser.swift | `parse(_:)` 基本调用 | Plugin 执行链路 |
| MyMarkdownVisitor.swift | visitDocument, visitHeading, visitParagraph, visitText, visitCodeBlock, visitImage (6/17) | visitInlineCode, visitLink, visitOrderedList, visitUnorderedList, visitListItem, visitTable, visitTableHead, visitTableBody, visitTableRow, visitTableCell, visitInlineHTML (11/17) |
| ASTPlugin.swift | — | 协议定义完全未测试，无具体实现测试 |

### Nodes 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MarkdownNode.swift | 间接覆盖 | 协议通过具体节点间接使用 |
| DocumentNode.swift | 部分覆盖 | 初始化 + children 访问 |
| HeaderNode.swift | 部分覆盖 | 初始化 + level 属性 |
| ParagraphNode.swift | 部分覆盖 | 初始化 + children 访问 |
| TextNode.swift | 部分覆盖 | text 属性间接验证 |
| CodeBlockNode.swift | 部分覆盖 | language + code 属性 |
| ImageNode.swift | 较好覆盖 | source, altText, title 全部验证 |
| InlineCodeNode.swift | **无覆盖** | — |
| LinkNode.swift | **无覆盖** | — |
| ListNode.swift | **无覆盖** | — |
| ListItemNode.swift | **无覆盖** | CheckboxState 枚举未测试 |
| TableNode.swift | **无覆盖** | TableAlignment, 全部子结构未测试 |
| MathNode.swift | **无覆盖** | Style 枚举, equation 属性未测试 |

### Layout 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| LayoutSolver.swift | 部分覆盖 | solve() 对 Header/Paragraph 路径已测试；Table/List/Link/InlineCode 路径未测试 |
| LayoutResult.swift | 部分覆盖 | 通过 solver 测试间接验证 size + attributedString |
| LayoutCache.swift | 较好覆盖 | getLayout, setLayout, clear 均已测试；CacheKey hash 碰撞和宽度容差未测试 |
| TextKitCalculator.swift | **无覆盖** | calculateSize() 仅被间接调用，未直接验证 |
| TypographyToken.swift | **无覆盖** | — |
| ColorToken.swift | **无覆盖** | — |

### Theme 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| Theme.swift | **无覆盖** | 默认主题初始化、自定义主题、Light/Dark 适配均未测试 |

### Highlighter 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| SplashHighlighter.swift | 部分覆盖 | highlight() 输出验证（仅 Swift 代码）；语言参数、颜色映射、字体转换未测试 |

### Math 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MathRenderer.swift | 少量覆盖 | render() 异步边界已触达；setupBackgroundWebView, processEquation, JS 错误处理, pending 队列未测试 |

### UI/Components 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| AsyncTextView.swift | **无覆盖** | configure(), 后台 Task, TextKit 2 绘制, traitCollectionDidChange 均未测试 |
| AsyncCodeView.swift | 极少覆盖 | 仅验证实例化；copy 按钮、动画、layoutSubviews 未测试 |
| AsyncImageView.swift | **无覆盖** | 下载/解码/降采样/取消全链路未测试 |

### UI/CollectionView 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MarkdownCollectionViewCell.swift | 部分覆盖 | configure + prepareForReuse 已测试；节点类型路由部分覆盖 |
| MarkdownCollectionView_iOS.swift | **无覆盖** | DataSource, sizeForItemAt, theme delegate 均未测试 |
| MarkdownCollectionView_macOS.swift | **无覆盖** | macOS 实现完全未测试 |
| MarkdownItemView.swift | **无覆盖** | macOS 实现完全未测试 |

### Utils 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| PerformanceProfiler.swift | 部分覆盖 | measure() 同步版本使用过；measureAsync() 未测试 |

---

## 未覆盖的关键缺口

### P0 — 核心功能无测试

| 缺口 | 影响 | 涉及文件 |
|------|------|---------|
| TextKitCalculator | 尺寸计算引擎，布局正确性基础 | TextKitCalculator.swift |
| Link 解析与渲染 | 超链接是 Markdown 基础元素 | LinkNode.swift, MyMarkdownVisitor.swift, LayoutSolver.swift |
| List / Checkbox | 列表和任务清单是高频使用功能 | ListNode.swift, ListItemNode.swift, MyMarkdownVisitor.swift, LayoutSolver.swift |
| Table | GFM 表格，包括列对齐 | TableNode.swift (+ Head/Body/Row/Cell), MyMarkdownVisitor.swift, LayoutSolver.swift |
| InlineCode | 行内代码是常用内联元素 | InlineCodeNode.swift, MyMarkdownVisitor.swift |

### P1 — 重要功能低覆盖

| 缺口 | 影响 | 涉及文件 |
|------|------|---------|
| AsyncImageView | 图片加载全链路（网络/本地/解码/降采样） | AsyncImageView.swift |
| macOS 平台 | 整个 macOS 渲染层零测试 | MarkdownCollectionView_macOS.swift, MarkdownItemView.swift |
| Theme 系统 | 主题初始化、Light/Dark 切换 | Theme.swift, TypographyToken.swift, ColorToken.swift |
| ASTPlugin | 插件中间件系统 | ASTPlugin.swift |
| MathRenderer 错误处理 | JS 执行失败、LaTeX 转义边界 | MathRenderer.swift |

### P2 — 质量提升

| 缺口 | 影响 | 涉及文件 |
|------|------|---------|
| AsyncTextView 绘制管道 | 后台 CoreGraphics 渲染验证 | AsyncTextView.swift |
| CollectionView DataSource | 数据源方法和 O(1) 尺寸查询 | MarkdownCollectionView_iOS.swift |
| 边界情况 | 空字符串、超长文本、畸形 Markdown、零宽度约束 | 所有模块 |
| 多语言语法高亮 | 仅测试了 Swift，未测试 Python/JS 等 | SplashHighlighter.swift |
| 性能基准测试 | 大文档渲染、滚动流畅度 | PerformanceProfiler.swift |

---

## 补全建议优先级

```
第一批 (P0): TextKitCalculator + List/Table/Link/InlineCode 节点解析与布局
第二批 (P1): AsyncImageView + macOS 平台 + Theme + ASTPlugin
第三批 (P2): AsyncTextView + CollectionView DataSource + 边界情况 + 性能测试
```
