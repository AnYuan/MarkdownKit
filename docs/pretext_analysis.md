# 深入了解 `@chenglou/pretext` 代码实现细节

`@chenglou/pretext` 是一个纯 JavaScript/TypeScript 实现的多行文本测量和排版（Layout）引擎库。它的核心设计理念是**彻底避免依赖 DOM 进行布局测量**（如 `getBoundingClientRect`、`offsetHeight` 等），从而避免触发高昂的浏览器重排（Reflow）。它使用浏览器原生的 Canvas Font 引擎作为真实的单行测量源，然后再通过纯数学计算来进行分行和排版。

本文档深入梳理了其核心代码实现细节，模块分工及相关技术挑战。

## 1. 核心架构与工作流

`pretext` 的工作流主要分为两步（Two-Phase Measurement）：

1. **预处理与测量（Preparation & Measurement）**：此阶段是耗时（一过性）的操作。
   - 对文本进行空白符合并/处理。
   - 使用 `Intl.Segmenter` 将文本分解为词（Words）、字符或黏合块。
   - 通过 `CanvasRenderingContext2D.measureText` 测量每个片段的宽度并进行缓存。
   - 若文本含有 Emoji 等特殊字符，进行特异性的宽度修正。
2. **排版计算（Layout / Line Breaking）**：在此阶段，排版是纯算术（Pure Arithmetic）的极速热路径（Hot Path）。
   - 给定一个 `maxWidth`，引擎只需要通过遍历上一步缓存的“宽度数组”来累加计算，即可得出断行点、行数和总体高度，不涉及任何 DOM 或 Canvas 调用，也不会创建多余的字符串或对象。

## 2. 模块解析

代码库主要切分为以下几个核心文件，每个文件职责单一且明确：

### 2.1 `analysis.ts` - 文本切割与词法分析

**核心职责**：将原始文本字符串进行规范化，并拆分为带语意的“排版片段（Segments）”。

- **空白符规范化**：根据 CSS 的 `white-space` 属性（`normal` 或 `pre-wrap`）清理文本。`normal` 会将连续的空格、换行符折叠为一个空格。
- **Intl.Segmenter 分词**：利用现代浏览器原生的 `Intl.Segmenter(locale, { granularity: 'word' })` 获取初步的分词结果。支持复杂的跨语言分词，如 CJK、泰语、阿拉伯语等。
- **排版片段分类（SegmentBreakKind）**：
  引擎会将字符归类为：`text`（普通文本）、`space`（可折叠空格）、`preserved-space`（保留空格）、`tab`（制表符）、`glue`（防断行黏合字符，如 NBSP）、`zero-width-break`（零宽断点）、`soft-hyphen`（软连字符）、`hard-break`（硬换行）。
- **启发式片段合并（Merging Heuristics）**：
  由于标准的 `Intl.Segmenter` 并不能完美匹配 CSS 的换行规则，`analysis.ts` 实现了大量的修补和合并逻辑：
  - **URL 与查询参数合并**：防止网址被从中间断开。
  - **标点符号黏连（Punctuation Sticky）**：保证单词后的标点符号（如 `better.`）被视为一个不可分割的测量单元。
  - **数字链与连字符处理**：处理电话号码、日期格式的连续性。
  - **语言学规则（Kinsoku Shori 等）**：处理 CJK 避头尾规则（如逗号不能出现在行首）、前向和后向黏合字符（如前引号不换行）、阿拉伯语与缅甸语的特定连字规则等。

### 2.2 `measurement.ts` - 基于 Canvas 的精准宽度测量

**核心职责**：在 Canvas 上测量分析阶段输出的各个文本片段的宽度，并处理不同浏览器的测量 Quirks（怪异行为）。

- **Canvas 测量缓存**：使用 `OffscreenCanvas`（支持的情况下）或 `document.createElement('canvas')` 获取 2D 上下文，利用 `measureText` 获取宽度，并通过 `Map` 针对 `(font, textSegment)` 进行全局缓存。
- **字素级测量（Grapheme Widths）**：为了支持 `overflow-wrap: break-word`（当单词比整行还宽时，强制在字符内部断开），在测量较长的词时，还会进一步利用 `Intl.Segmenter(..., { granularity: 'grapheme' })` 去测量每个字素（Grapheme）的宽度。
- **Emoji 宽度修正（Emoji Canvas Inflation）**：
  *这是一个非常经典的浏览器怪异行为*。在 macOS 下（特别是 Safari / Chrome / Firefox 在特定小字号时），Canvas 测量出的 Apple Color Emoji 的宽度可能会明显**大于**其实际在 DOM 中渲染的宽度。
  - 库中实现了一个自动检测机制：动态插入一个隐藏的 `<span>😀</span>`，对比其 `getBoundingClientRect().width` 与 Canvas 的 `measureText`，计算出差值（Correction）。
  - 在后续针对包含 Emoji 的片段进行宽度累加时，会减去这个恒定差值，以达到与浏览器 DOM 排版 100% 一致。
- **浏览器特性感知（Engine Profile）**：针对 Safari 和 Chromium 的细微排版差异（如软连字符优先级、是否携带闭合引号进入下行等），代码中通过 UA 检测生成了 `EngineProfile`，实施差异化的排版策略。

### 2.3 `line-break.ts` - 纯算术断行引擎

**核心职责**：接管已经测好宽度的数组，利用一个高速指针循环计算换行（Line Breaking）。

- **架构设计**：数据被组织成了并行数组（Parallel Arrays），如 `widths[]`, `kinds[]`, `breakableWidths[]` 等。这种设计主要是出于极致的性能考虑（Data Locality 与免除对象分配）。
- **Fast Path 与 Slow Path**：
  - `countPreparedLinesSimple` / `walkPreparedLinesSimple`：针对普通文本的高速路径。只要没有出现复杂的特殊字符（如 Tab 或软连字符），就可以在单重循环中完成简单的宽度累加与边界判断。
  - `walkPreparedLines`：全量功能的断行引擎。它严格模拟了 CSS `white-space: normal` 以及 `overflow-wrap: break-word` 的行为。
- **具体换行规则还原**：
  - 如果一个单词超出了 `maxWidth` 限制，优先在空格处断行。
  - 如果单个单词长度超过 `maxWidth`，激活 Grapheme 级别的强行拆分逻辑，利用预计算好的 `breakableWidths` 数组步进累加。
  - 尾部悬挂（Trailing Whitespace Hang）：行尾的空格宽度在匹配 `maxWidth` 时不计算在内（`lineEndFitAdvances` 的控制），高度还原了 CSS 处理行尾空格的默认行为。
  - 软连字符（Soft Hyphen）宽度补偿处理：只有发生实际断行时，软连字符的显示宽度才会被计入本行。

### 2.4 `bidi.ts` - 双向文本（Bi-directional Text）处理

**核心职责**：为混合从左到右（LTR）与从右到左（RTL）的复杂排版，提供基础的双向嵌入层级（Embedding Levels）计算。

- 算法直接派生于 `pdf.js` 中 Sebastian Markbage 实现的轻量级 BiDi 解析器。
- 代码内部实现了一个字符状态机，对包含 Unicode 范围的字符进行类别分类（如 `L`, `R`, `AL`, `AN`, `EN` 等）。
- 最终为每个排版段落输出对应的 `Int8Array` 层级。
- **注意**：断行引擎自身并不依赖 BiDi 层级（换行宽度计算不受显示方向影响），该元数据是暴露给“自定义渲染器（Custom Renderer，如 Canvas/WebGL 渲染器）”使用，指导它们以正确的物理顺序从左至右绘制文本。

### 2.5 `layout.ts` - 门面与 API 封装

**核心职责**：整合上述模块，对外暴露简洁、不易滥用的 API。

主要分为两个层级的 API：
1. **尺寸计算层（UseCase 1）**：
   - `prepare(text, font, options)`：返回一个不透明句柄 `PreparedText`，不暴漏内部数组。
   - `layout(prepared, maxWidth, lineHeight)`：极速热路径，仅返回 `{ height, lineCount }`，可放在 `ResizeObserver` 或 React 的 `Render` 阶段的高频执行。
2. **自定义渲染层（UseCase 2）**：
   - `prepareWithSegments`：返回包含原始字符串的富句柄。
   - `layoutWithLines` / `walkLineRanges` / `layoutNextLine`：除了高度外，还会构建并返回每一行的具体文本、宽度、以及在原文本中的游标 `start` 和 `end`。这对于需要在 WebGL、SVG 或 Canvas 中手动重绘文字的用户至关重要。

## 3. 技术亮点与启发

1. **并行数组 (Structure of Arrays, SoA)**：
   Pretext 在内部将每一个分词抽象为一系列基础类型数组（`widths`, `kinds`, `lineEndFitAdvances`），而不是 `[{ text, width, kind }]` 对象数组。这避免了大规模的内存分配与垃圾回收（GC），使得其性能达到极致（约 0.09ms 可以完成 500 次排版计算）。
2. **彻底解决排版碎片化问题**：
   利用 `Intl.Segmenter` 将繁重的多语言规则交给底层 C++ 引擎（V8/JSC），仅在 JavaScript 层面上修补符合前端 CSS 直觉的合并逻辑，极大地降低了实现复杂性。
3. **AI-Friendly 的思路**：
   开发者在 README 中特意提到，使用浏览器引擎做基准（Ground Truth），而不是自己实现字体解析器（如 Opentype.js），这不仅免除了巨大的库体积（几十MB），也是一种极佳的工程折衷。这种利用“黑盒 API 输出特征建立规则”的思路，非常适合由 AI 协助分析与迭代。

## 4. 局限性

1. **目前主要支持常规 Web 设置**：即 `word-break: normal`, `overflow-wrap: break-word`, `line-break: auto`。暂不支持其他花式的断行模式。
2. **系统字体陷阱**：在 macOS 下使用 `system-ui` 作为 font name 时，Canvas 分辨出来的字体变体可能跟 DOM 的不同，因此强烈建议使用确切的字体名称（如 `'16px Inter'`）。

---

*（本文档生成于对 `https://github.com/chenglou/pretext` 的全面源码分析）*
