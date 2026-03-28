# MarkdownKit Layout 引擎实现细节分析

`MarkdownKit` 的 Layout 模块是其高性能渲染体系的核心。为了能够在解析巨型 Markdown 文档时依然保持 UI 的如丝般顺滑，MarkdownKit 采用了一套**严格的后台异步计算与预排版机制**。

本文档深入梳理了 `Sources/MarkdownKit/Layout` 目录下的核心实现细节，阐述其架构设计与性能优化手段。

## 1. 核心架构设计理念

MarkdownKit Layout 的核心目标是：**绝不在主线程（Main Thread）执行任何繁重的富文本生成或尺寸测量计算**。

其工作流大致如下：
1. **输入**：从 Parser 获得一棵抽象语法树（AST），即 `MarkdownNode`。
2. **构建富文本**：根据 `Theme` 配置，将节点递归转化为样式丰富的 `NSAttributedString`。
3. **后台测量**：在后台线程利用 `TextKitCalculator` 提前测量出这段富文本在给定 `maxWidth` 下的精确包围盒（Bounding Box）。
4. **缓存与输出**：将上述节点、计算好的 `NSAttributedString` 和 `CGSize` 封装为绝对不可变的 `LayoutResult` 结构体，存入内存缓存，并交给 UI 层渲染。

此架构深受 AsyncDisplayKit（Texture）思想的影响，使得如 `UICollectionView` 或 `UITableView` 在请求 `sizeForItem` 时，耗时几乎为 0。

## 2. 核心模块解析

### 2.1 `LayoutSolver.swift` - 排版调度中心
`LayoutSolver` 是所有排版操作的入口，提供异步（`solve`）和同步（`solveSync`）两种调用方式。

- **协作式多任务 (Cooperative Multitasking)**：在 `solve` 开头调用了 `await Task.yield()`，将控制权短暂交还给系统，防止解析上万行文档时占死后台线程而导致卡顿。
- **递归排版**：对诸如 `DocumentNode` 的容器节点，它会递归遍历子节点，将子节点的 `LayoutResult` 组合到自身的 `children` 数组中。
- **自定义绘制拦截**：并不是所有元素都用 TextKit 排版。比如 iOS 上的 `ThematicBreakNode`（分割线）或特定样式的 `TableNode`（表格），`LayoutSolver` 会将其拦截，并赋予一个原生的 `customDraw` 闭包（基于 `CGContext` 的直接绘制指令），绕过 TextKit 从而大幅提升性能。

### 2.2 `AttributedStringBuilder.swift` - 富文本与样式映射
该类专门负责将 `MarkdownNode` 映射为 `NSAttributedString`。

- 它深度结合了外部注入的 `Theme` 对象，将抽象的 `TextNode`, `StrongNode`, `HeaderNode` 转化为包含 `.font`, `.foregroundColor`, `.paragraphStyle` 的字典。
- **代码高亮集成**：遇到 `CodeBlockNode` 时，同步调用内部的 `SplashHighlighter`，生成带有语法高亮色彩的富文本。
- **扩展节点支持**：异步等待 `DiagramNode` (Mermaid图表) 和 `MathNode` (公式) 适配器的渲染结果，将其以 `NSTextAttachment` 的形式嵌入字符串中。
- **列表与缩进处理**：通过高度定制 `NSMutableParagraphStyle` 的 `headIndent` 和 `firstLineHeadIndent`，实现了多级列表、复选框的精准对齐。

### 2.3 `TextKitCalculator.swift` - 后台尺寸测量引擎
这是一个严格在后台队列执行的工具类。

- 它的核心职责是获取一个 `NSAttributedString` 和一个 `maxWidth`，计算出 `CGSize`。
- **底层选型**：为了与 UI 层渲染引擎（如 `AsyncTextView`）对齐并防止高度低估，它显式使用了 **TextKit 1 (`NSLayoutManager`)**。
- **并发安全护城河**：由于 macOS/iOS 内部的 CoreText / NSFont 在高并发下解析字体 Fallback 时极易引发 Crash，这个类在布局管线的核心调用外加上了 `os_unfair_lock` 互斥锁，以牺牲极小部分并行度换取了绝对的线程安全。

### 2.4 `LayoutCache.swift` - 内容指纹驱动的高速缓存
MarkdownKit 没有简单地用 UUID 来做缓存，而是实现了一套**基于内容语义指纹（Content Fingerprinting）**的缓存机制。

- **为什么这么做？** 在流式打字（Streaming）场景下，每一次键盘输入都会导致 Parser 生成一棵全新的 AST 树（全新的 UUID）。但对于未修改的段落，它们的内容是不变的。
- **实现方式**：`LayoutCache` 通过深度遍历节点的属性（如 `node.text`, `header.level` 等），利用 Swift 的 `Hasher` 快速计算出一个 Deterministic Hash。
- **缓存 Key**：`CacheKey` 由此 `contentHash` 和 `width` 联合组成。因此，即使节点对象换了，只要文字没变且容器宽度没变，就能瞬间命中缓存（O(1) 复杂度返回 `LayoutResult`）。

### 2.5 `LayoutResult.swift` - 绝对不可变的数据载体
这只是一个轻量级的 Struct（`@unchecked Sendable` 安全），包含：
- `node`: 原始 AST 节点。
- `size`: 预计算的宽和高。
- `attributedString`: 包含完整属性的渲染文本。
- `customDraw`: 可选的 `CGContext` 直接绘制指令闭包。

由于它是纯数据类型且不可变，可以极其安全地在后台排版线程与主 UI 线程间穿梭传递。

## 3. 表格渲染的跨平台差异性挑战

Markdown 的表格渲染一直是富文本引擎的痛点。MarkdownKit 巧妙地实现了跨平台的差异化策略：

### 3.1 macOS (AppKit): 原生 `NSTextTable` 支持
`TableAttributedStringBuilder.swift` 针对 macOS 利用了 AppKit 强大的原生表格能力。
- 将节点映射为 `NSTextTableBlock`。
- 通过设置 `textTable.collapsesBorders = true` 以及细致的宽度计算，完美输出了原生支持换行与自适应列宽的表格。

### 3.2 iOS (UIKit): 弃用 `NSTextTable`，拥抱 `CGContext` 绘制
iOS 的 TextKit 极度缺乏对表格的内建支持（没有 `NSTextTable` 等价物）。
- **`TableCardRenderer.swift` (Card 渲染)**：为了实现漂亮的视觉效果（卡片式圆角、边框、斑马纹），MarkdownKit 在 iOS 上通过 `TableCardRenderer` 遍历每一个表格单元格单独进行测量。
- **直接光栅化**：它生成了一系列 `CellLayout` 坐标，并将这些数据包装为一个 `customDraw` 闭包（封装了纯底层的 `CGContext.fill`, `stroke`, `draw` 指令）。
- **降级方案 (Narrow Fallback)**：对于列数极多或屏幕极窄的情况，如果卡片式渲染不适用，`TableAttributedStringBuilder` 提供了一个将表格“序列化”为由 `|` 和 `─` 组成的纯文本降级展现机制。

## 4. 总结

MarkdownKit 的 Layout 系统展现了极高的工程成熟度。它通过 **内容 Hash 缓存**、**TextKit 1 后台精确测量**、**不可变状态传递 (LayoutResult)** 以及 **iOS/macOS 因地制宜的特异化渲染**，成功达成了一个极低主线程开销、支持高度并发并且表现极其稳定的 Markdown 渲染引擎基座。
