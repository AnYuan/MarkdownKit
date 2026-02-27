# MarkdownKit 单元测试覆盖率报告

> 最近更新: 2026-02-27
> 测试框架: XCTest
> Swift 版本: 6.2+

---

## 总览 (最新)

| 指标 | 初始 | 第一轮 | 第二轮 (当前) |
| ------ | ------ | ------ | ------ |
| 测试文件 | 3 | 11 | 22 (+11) |
| 测试方法 | 5 | 76 | 165 (+89) |
| 有测试覆盖的源文件 | 5 / 36 (14%) | 30 / 36 (83%) | 34 / 36 (94%) |
| 有测试覆盖的模块 | 4 / 9 (44%) | 9 / 9 (100%) | 9 / 9 (100%) |
| 预估行覆盖率 | ~15-20% | ~75-80% | ~88-92% |
| 预估分支覆盖率 | ~8-12% | ~60-65% | ~78-82% |

### 第二轮新增亮点

- **内联格式化全覆盖**: StrongNode、EmphasisNode、StrikethroughNode、BlockQuoteNode、ThematicBreakNode 从零覆盖到解析+布局双重验证
- **macOS UI 从零到完整**: MarkdownItemView 7 个测试 + MarkdownCollectionView 初始化测试
- **插件系统深度测试**: 空返回、重复、三插件链式、顺序无关性、组合嵌套等边界场景
- **端到端集成**: 复杂文档全链路、多插件集成、宽度约束、自定义主题、大文档性能

---

## 各模块覆盖率

| 模块 | 源文件数 | 覆盖状态 | 预估覆盖率 |
|------|---------|---------|-----------|
| Parsing (解析) | 6 | 较好覆盖 | ~85% |
| Nodes (AST 节点) | 17 | 较好覆盖 | ~80% |
| Layout (布局引擎) | 6 | 较好覆盖 | ~85% |
| Theme (主题) | 1 | 已覆盖 | ~90% |
| Highlighter (语法高亮) | 1 | 较好覆盖 | ~75% |
| Math (数学渲染) | 1 | 部分覆盖 | ~40% |
| Diagrams (图表) | 1 | 较好覆盖 | ~90% |
| UI/Components (异步组件) | 3 | 部分覆盖 | ~50% |
| UI/CollectionView (虚拟化) | 4 | 部分覆盖 | ~60% |
| Utils (工具) | 1 | 较好覆盖 | ~80% |

---

## 测试套件明细 (22 个测试文件)

### 解析层测试

#### MarkdownKitTests.swift (2 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testBasicCommonMarkParsing()` | MarkdownParser.parse() → DocumentNode 子节点数量、HeaderNode level、ParagraphNode 文本内容 |
| `testCodeAndImageGFMParsing()` | CodeBlockNode language + code 属性、ImageNode source/altText/title 属性 |

#### ParserInlineFormattingTests.swift (12 个测试) ✨ 新增

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testBoldTextParsesToStrongNode()` | `**bold**` → ParagraphNode > StrongNode > TextNode |
| `testItalicTextParsesToEmphasisNode()` | `*italic*` → ParagraphNode > EmphasisNode > TextNode |
| `testStrikethroughParsesToStrikethroughNode()` | `~~struck~~` → ParagraphNode > StrikethroughNode > TextNode |
| `testBlockQuoteParsesToBlockQuoteNode()` | `> quote` → BlockQuoteNode > ParagraphNode > TextNode |
| `testThematicBreakParsesToThematicBreakNode()` | `---` → ThematicBreakNode |
| `testNestedBlockQuoteWithInlineFormatting()` | 引用块中嵌套 StrongNode + EmphasisNode |
| `testMixedBoldAndItalic()` | `***both***` → 嵌套 StrongNode/EmphasisNode |
| `testBoldInsideStrikethrough()` | `~~**bold**~~` → StrikethroughNode > StrongNode |
| `testDeeplyNestedList()` | 3 层嵌套列表结构验证 |
| `testTableWithInlineFormattingInCells()` | 表格单元格内 StrongNode + EmphasisNode |
| `testSoftBreakBecomesSpace()` | 软换行被解析为空格/多 TextNode |
| `testLineBreakBecomesNewline()` | 硬换行（两个尾随空格）产生多段内联子节点 |

#### ParserLinkListTableTests.swift (11 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testLinkWithDestination()` | LinkNode destination 属性 |
| `testLinkWithoutTitle()` | LinkNode title 为 nil |
| `testInlineCodeParsing()` | InlineCodeNode code 属性 |
| `testUnorderedListParsing()` | ListNode isOrdered=false |
| `testOrderedListParsing()` | ListNode isOrdered=true |
| `testCheckboxTaskListParsing()` | CheckboxState.checked / .unchecked |
| `testBasicTableParsing()` | TableNode > TableHead/TableBody > TableRow > TableCell |
| `testTableWithColumnAlignments()` | TableNode.columnAlignments (left/center/right) |
| `testTableCellTextContent()` | TableCellNode 文本提取 |
| `testInlineHTMLFallsBackToTextNode()` | `<br>` 降级为 TextNode |
| `testHTMLBlockFallsBackToTextNode()` | HTML 块降级为 TextNode |

### 插件测试

#### ASTPluginTests.swift (13 个测试, +8 新增)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testParserWithNoPlugins()` | 空插件列表不影响解析 |
| `testSinglePluginTransformsAST()` | RedactPlugin 替换 TextNode |
| `testMultiplePluginsChainedInOrder()` | 多插件链式执行 |
| `testPluginReceivesTopLevelNodes()` | 插件收到顶层 HeaderNode + ParagraphNode |
| `testPluginCanInjectMathNode()` | 插件注入 MathNode |
| `testPluginReturningEmptyArrayProducesEmptyDocument()` | ✨ 插件返回空数组 → 空文档 |
| `testPluginDuplicatingNodesDoublesChildren()` | ✨ 重复插件倍增子节点 |
| `testAllThreeBuiltInPluginsChained()` | ✨ Math + Diagram + Details 三插件链式验证 |
| `testPluginOrderMathBeforeDiagram()` | ✨ Math 先于 Diagram 顺序 |
| `testPluginOrderDiagramBeforeMath()` | ✨ Diagram 先于 Math 顺序 |
| `testPluginDoesNotModifyUnrelatedNodes()` | ✨ DiagramExtractionPlugin 不修改段落 |
| `testPluginPreservesNodeIDs()` | ✨ 直通插件保持节点数量和唯一 ID |
| `testDetailsAndDiagramPluginComposition()` | ✨ Details 内嵌 Diagram 的组合验证 |

#### MathExtractionPluginTests.swift (6 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testFencedMathCodeBlockConvertsToBlockMathNode()` | `` ```math `` → MathNode(block) |
| `testNonMathFencedCodeBlockRemainsCodeBlockNode()` | 非 math 语言不转换 |
| `testInlineMathParsesMultipleExpressionsInSingleParagraph()` | `$x$` 内联数学 |
| `testEscapedDollarDoesNotCreateUnexpectedInlineMath()` | 转义 `\$` 不产生数学节点 |
| `testUnterminatedInlineMathFallsBackToText()` | 未闭合 `$` 降级为文本 |
| `testBlockMathAcrossParagraphsConvertsToSingleMathNode()` | `$$...$$` 块级数学 |

#### DiagramExtractionPluginTests.swift (3 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testMermaidFenceConvertsToDiagramNode()` | `` ```mermaid `` → DiagramNode |
| `testUnsupportedFenceLanguageRemainsCodeBlock()` | 不支持语言保持 CodeBlockNode |
| `testDiagramFenceInsideDetailsBodyConvertsWhenPluginsChained()` | Details 内嵌 Diagram 插件链 |

#### DetailsExtractionPluginTests.swift (4 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testDetailsBlockWithInlineSummaryConvertsToDedicatedNode()` | `<details>` → DetailsNode |
| `testDetailsOpenAttributeSetsExpandedState()` | `<details open>` → isOpen=true |
| `testNestedDetailsAreParsedRecursively()` | 嵌套 `<details>` 递归解析 |
| `testMalformedDetailsWithoutClosingTagFallsBackToOriginalNodes()` | 畸形 HTML 降级 |

### 节点模型测试

#### NodeModelTests.swift (18 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testTextNodeIsLeaf()` | TextNode 叶节点结构 |
| `testInlineCodeNodeIsLeaf()` | InlineCodeNode 叶节点 |
| `testCodeBlockNodeIsLeaf()` / `testCodeBlockNodeNilLanguage()` | CodeBlockNode 属性 |
| `testImageNodeIsLeaf()` / `testImageNodeNilProperties()` | ImageNode 属性 |
| `testMathNodeIsLeaf()` | MathNode block/inline |
| `testDocumentNodeHoldsChildren()` | DocumentNode children |
| `testHeaderNodeProperties()` | HeaderNode level |
| `testParagraphNodeHoldsChildren()` | ParagraphNode children |
| `testLinkNodeProperties()` | LinkNode destination |
| `testListNodeIsOrdered()` | ListNode ordered/unordered |
| `testListItemNodeCheckboxStates()` | CheckboxState 枚举 |
| `testTableNodeColumnAlignments()` | TableNode 列对齐 |
| `testDetailsNodeProperties()` | DetailsNode summary/isOpen |
| `testSummaryNodeHoldsChildren()` | SummaryNode children |
| `testDiagramNodeProperties()` | DiagramNode language/source |
| `testEachNodeHasUniqueID()` | UUID 唯一性 |

### 布局引擎测试

#### LayoutTests.swift (3 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testBackgroundLayoutSizingAndCaching()` | LayoutSolver.solve() 异步布局 + LayoutCache 缓存 |
| `testSyntaxHighlighting()` | SplashHighlighter 多色输出 |
| `testMathJaxBackgroundRendering()` | MathRenderer 异步渲染 (UIKit) |

#### LayoutSolverExtendedTests.swift (14 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testListLayoutProducesNonZeroSize()` | 列表布局非零尺寸 |
| `testCheckboxListLayoutIncludesSymbols()` | ☑ / ☐ 符号 |
| `testTableLayoutProducesAttributedString()` | 表格 AttributedString 输出 |
| `testTableLayoutRetainsHeaderContent()` | 表头内容保留 |
| `testTableLayoutUsesNativeTextTableBlocks()` | NSTextTableBlock 使用 |
| `testTableLayoutCentersAllCellContent()` | 单元格居中对齐 |
| `testTableLayoutAppliesHeaderAndAlternatingRowBackgrounds()` | 表头背景 + 斑马条纹 |
| `testClosedDetailsLayoutShowsOnlySummaryRow()` | ▶ 折叠状态 |
| `testOpenDetailsLayoutShowsSummaryAndBody()` | ▼ 展开状态 |
| `testHeaderLevelsUseCorrectThemeTokens()` | H1-H3 主题 token |
| `testCodeBlockLayoutUsesSplashHighlighter()` | 代码块语法高亮 |
| `testCodeBlockLayoutPrependsLanguageLabelWhenPresent()` | 语言标签（大写） |
| `testCodeBlockLayoutOmitsLanguageLabelWhenMissing()` | 无标签代码块 |
| `testEmptyDocumentLayoutProducesZeroChildren()` | 空文档边界 |

#### InlineFormattingLayoutTests.swift (14 个测试) ✨ 新增

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testStrongNodeLayoutAppliesBoldFont()` | 粗体字体 trait 验证 |
| `testEmphasisNodeLayoutAppliesItalicFont()` | 斜体字体 trait 验证 |
| `testStrikethroughNodeLayoutAppliesStrikethroughAttribute()` | 删除线 .strikethroughStyle 属性 |
| `testBlockQuoteLayoutAppliesIndentAndQuoteBar()` | 引用块 ┃ 前缀 + headIndent≥16 + 灰色前景 |
| `testBlockQuoteBarUsesBlueColor()` | 引用块竖线 systemBlue 颜色 |
| `testThematicBreakLayoutRendersHorizontalRule()` | 40 个 ─ 字符 + 灰色 |
| `testBoldInsideParagraphLayoutMixesFonts()` | 混合粗体/普通多 font run |
| `testItalicInsideParagraphLayoutMixesFonts()` | 混合斜体/普通多 font run |
| `testStrikethroughInsideParagraphMixesAttributes()` | 删除线仅覆盖部分文本 |
| `testBoldAndItalicCombined()` | `***text***` 同时含粗体+斜体 trait |
| `testBoldWithStrikethrough()` | `**~~text~~**` 粗体 + 删除线组合 |
| `testInlineCodeInsideParagraph()` | 内联代码背景色 |
| `testLinkInsideParagraph()` | 链接蓝色 + 下划线 + .link URL |
| `testImageAltTextFallback()` | 图片 `[alt]` + secondaryLabelColor |
| `testMathLayoutProducesOutput()` | 数学公式输出（渲染图或降级文本） |

#### DiagramLayoutTests.swift (8 个测试, +6 新增)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testDiagramLayoutFallsBackToCodeBlockWhenNoAdapterRegistered()` | 无适配器时降级为代码块 |
| `testDiagramLayoutUsesRegisteredAdapterOutput()` | 已注册适配器输出 |
| `testRegistryAdapterReturnsNilForUnregisteredLanguage()` | ✨ 空注册表返回 nil |
| `testRegistryRegisterAndRetrieve()` | ✨ 注册并检索适配器 |
| `testRegistryOverwriteExistingAdapter()` | ✨ 覆盖已注册适配器 |
| `testRegistryMultipleLanguages()` | ✨ 多语言注册/查询 |
| `testRegistryInitWithAdapters()` | ✨ 字典初始化 |
| `testDiagramLanguageAllCases()` | ✨ DiagramLanguage 枚举 4 个 case |

#### LayoutCacheEdgeCaseTests.swift (9 个测试, +5 新增)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testCacheMissForDifferentWidth()` | 不同宽度独立缓存 |
| `testCacheExactWidthHit()` | 精确宽度命中 |
| `testCacheCustomCountLimit()` | 自定义缓存限制 |
| `testClearRemovesAllEntries()` | clear() 清空全部 |
| `testCacheRequiresExactWidthMatchDueToHashing()` | ✨ 宽度匹配受 hash 约束（精确匹配） |
| `testRepeatedCacheAccessDoesNotCrash()` | ✨ 100 次快速读写稳定性 |
| `testCacheSameNodeDifferentWidths()` | ✨ 同节点 5 种宽度独立检索 |
| `testCacheEvictionAtCountLimit()` | ✨ countLimit=2 时驱逐验证 |

#### TextKitCalculatorTests.swift (4 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testEmptyStringReturnsZeroSize()` | 空字符串边界 |
| `testSingleLineTextFitsWithinWidth()` | 单行文本尺寸 |
| `testLongTextWrapsAndIncreasesHeight()` | 长文本自动换行 |
| `testDifferentFontSizesProduceDifferentHeights()` | 不同字号影响高度 |

### 主题与配置测试

#### ThemeAndTokenTests.swift (7 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testTypographyTokenDefaultValues()` | 默认 lineHeightMultiple=1.2, paragraphSpacing=16 |
| `testTypographyTokenCustomValues()` | 自定义初始化 |
| `testColorTokenDefaultBackground()` | 默认 .clear 背景 |
| `testColorTokenCustomBackground()` | 自定义颜色 |
| `testDefaultThemeInitialization()` | Theme.default 字号验证 |
| `testCustomThemeInitialization()` | 自定义主题创建 |
| `testCustomThemeFlowsThroughLayoutSolver()` | 主题流入布局引擎 |

### 高亮与性能测试

#### HighlighterAndProfilerTests.swift (7 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testHighlightSwiftCodeProducesMultipleRuns()` | Swift 语法高亮多色 |
| `testHighlightEmptyStringProducesEmptyResult()` | 空字符串边界 |
| `testHighlightWithCustomTheme()` | 自定义主题集成 |
| `testHighlightPreservesCodeContent()` | 高亮后内容保留 |
| `testMeasureSyncReturnsNonNegativeTime()` | 同步测量非负 |
| `testMeasureAsyncReturnsNonNegativeTime()` | 异步测量非负 |
| `testMeasureMetricRawValues()` | Metric 枚举值验证 |

### 边界情况测试

#### EdgeCaseTests.swift (14 个测试)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testParseEmptyString()` | 空输入 |
| `testParseWhitespaceOnly()` | 纯空白输入 |
| `testNestedListParsing()` | 多级嵌套列表 |
| `testMixedContentDocument()` | 复杂混合文档 |
| `testAllSixHeaderLevels()` | H1-H6 全部级别 |
| `testSpecialCharactersInText()` | &, 引号等特殊字符 |
| `testUnicodeContentParsing()` | Emoji, CJK 字符 |
| `testZeroWidthLayoutDoesNotCrash()` | 零宽度约束 |
| `testVeryLargeWidthLayout()` | 超大宽度约束 |
| `testVeryLongTextLayout()` | 万字长文档 |
| `testCodeBlockWithNoLanguage()` | 无语言代码块 |
| `testEmptyCodeBlock()` | 空代码块 |
| `testLayoutResultInitDefaults()` | LayoutResult 默认初始化 |

### UI 组件测试

#### UIComponentsTests.swift (1 个测试, 仅 iOS)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testVirtualizationPurging()` | Cell 挂载/回收 AsyncTextView/AsyncCodeView (UIKit) |

#### UIComponentsPlatformTests.swift (13 个测试, 仅 iOS)

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testAsyncImageViewConfigureWithNonImageNodeIsNoop()` | 类型不匹配处理 |
| `testAsyncImageViewConfigureWithNilSourceIsNoop()` | nil source 处理 |
| `testAsyncImageViewConfigureWithInvalidURLIsNoop()` | 无效 URL 处理 |
| `testAsyncCodeViewHasSubviews()` | 子视图结构 (textView + copyButton) |
| `testAsyncCodeViewLayoutSubviews()` | 布局 16px padding |
| `testAsyncTextViewConfigureWithNilString()` | nil AttributedString 处理 |
| `testCellRoutesImageNodeToAsyncImageView()` | ImageNode 路由 |
| `testCellRoutesCodeBlockToAsyncCodeView()` | CodeBlockNode 路由 |
| `testCellRoutesDefaultNodeToAsyncTextView()` | 默认路由 |
| `testCellReconfigurePurgesOldView()` | 视图替换 |
| `testCellPrepareForReuseRemovesAllSubviews()` | 回收清理 |

#### MacOSUIComponentsTests.swift (8 个测试) ✨ 新增

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testLoadViewCreatesNSView()` | loadView() → wantsLayer=true |
| `testConfigureAddsTextViewSubview()` | configure() 添加 NSTextView 子视图 |
| `testConfigureWithCodeBlockSetsBackgroundAndCornerRadius()` | 代码块 drawsBackground + cornerRadius=6 |
| `testConfigureWithNilAttributedStringAddsNoSubview()` | nil AttrString → 0 子视图 |
| `testConfigureWithEmptyAttributedStringAddsNoSubview()` | 空 AttrString → 0 子视图 |
| `testPrepareForReuseRemovesHostedView()` | prepareForReuse() 清理 |
| `testReconfigureReplacesHostedView()` | 二次 configure() 替换而非叠加 |
| `testInitializesWithScrollViewSubview()` | MarkdownCollectionView 含 NSScrollView |

### 集成测试

#### IntegrationPipelineTests.swift (10 个测试) ✨ 新增

| 测试方法 | 覆盖内容 |
|---------|---------|
| `testComplexDocumentEndToEndLayout()` | H1 + 段落 + 粗体 + 列表 + 代码 + 表格 + 分隔线端到端 |
| `testDocumentWithAllInlineFormattingTypes()` | 单段落内粗/斜/删除/代码/链接/图片全内联类型 |
| `testMultiPluginDocumentIntegration()` | Math + Diagram + Details 三插件全链路 |
| `testLayoutWidthConstraintRespected()` | 所有子布局宽度≤约束 |
| `testLayoutWithCustomThemeProducesCorrectFonts()` | 自定义主题字号正确流入 |
| `testNestedListLayoutProducesIndentation()` | 嵌套列表缩进样式 |
| `testOrderedListLayoutProducesNumberedPrefixes()` | 有序列表 "1. " / "2. " / "3. " 前缀 |
| `testBlockQuoteInsideDetailsLayoutIntegration()` | Details 内嵌 BlockQuote 的 ▼ + ┃ 渲染 |
| `testLargeDocumentLayoutPerformance()` | 50+ 节点大文档布局完成 |
| `testEmptyAndWhitespaceDocumentLayout()` | 空/纯空白文档 → 0 children |

---

## 各源文件覆盖详情

### Parsing 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MarkdownParser.swift | 较好覆盖 | parse()、插件链路均已测试 |
| MarkdownKitVisitor.swift | 较好覆盖 | 15/17 visit 方法已覆盖 (visitStrong, visitEmphasis, visitStrikethrough, visitBlockQuote, visitThematicBreak 新增覆盖) |
| ASTPlugin.swift | 较好覆盖 | 多种自定义插件 + 内置插件边界全面测试 |
| MathExtractionPlugin.swift | 较好覆盖 | block/inline/escape/unterminated 全路径 |
| DiagramExtractionPlugin.swift | 较好覆盖 | mermaid 转换 + 降级 + 嵌套 |
| DetailsExtractionPlugin.swift | 较好覆盖 | open/closed/nested/malformed |

### Nodes 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MarkdownNode.swift | 间接覆盖 | 协议通过所有具体节点间接使用 |
| DocumentNode.swift | 较好覆盖 | 初始化 + children + 布局 |
| HeaderNode.swift | 较好覆盖 | level 属性 + H1-H6 解析 + 布局 |
| ParagraphNode.swift | 较好覆盖 | children + 内联格式化 |
| TextNode.swift | 较好覆盖 | text 属性 + 软/硬换行 |
| CodeBlockNode.swift | 较好覆盖 | language + code + 布局高亮 |
| ImageNode.swift | 较好覆盖 | source/altText/title + 布局降级 |
| InlineCodeNode.swift | 较好覆盖 | code + 背景色布局 |
| LinkNode.swift | 较好覆盖 | destination + 蓝色/下划线/URL 布局 |
| StrongNode.swift | 较好覆盖 | 解析 + 粗体 trait 布局 |
| EmphasisNode.swift | 较好覆盖 | 解析 + 斜体 trait 布局 |
| StrikethroughNode.swift | 较好覆盖 | 解析 + 删除线属性布局 |
| BlockQuoteNode.swift | 较好覆盖 | 解析 + ┃ 前缀 + 缩进布局 |
| ThematicBreakNode.swift | 较好覆盖 | 解析 + ─×40 水平线布局 |
| ListNode.swift | 较好覆盖 | 有序/无序 + 嵌套 + 布局 |
| ListItemNode.swift | 较好覆盖 | CheckboxState + 布局前缀 |
| TableNode.swift | 较好覆盖 | 对齐 + NSTextTableBlock + 斑马条纹 |
| MathNode.swift | 较好覆盖 | block/inline style + 布局 |
| DiagramNode.swift | 较好覆盖 | language/source + 适配器布局 |
| DetailsNode.swift | 较好覆盖 | isOpen + summary + 折叠/展开布局 |

### Layout 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| LayoutSolver.swift | 较好覆盖 | 所有 block 类型 + 所有 inline 类型布局路径已测试 |
| LayoutResult.swift | 较好覆盖 | node/size/attributedString/children |
| LayoutCache.swift | 较好覆盖 | get/set/clear + 精确宽度匹配 + 驱逐 + 并发稳定性 |
| TextKitCalculator.swift | 较好覆盖 | 空字符串/单行/换行/字号差异 |
| TypographyToken.swift | 较好覆盖 | 默认值 + 自定义值 |
| ColorToken.swift | 较好覆盖 | 默认背景 + 自定义颜色 |

### Theme 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| Theme.swift | 较好覆盖 | 默认主题 + 自定义主题 + 流入布局引擎 |

### Diagrams 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| DiagramAdapter.swift | 较好覆盖 | 注册/检索/覆盖/多语言/字典初始化 + DiagramLanguage 枚举 |

### Highlighter 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| SplashHighlighter.swift | 较好覆盖 | highlight() 多色输出 + 空字符串 + 自定义主题 + 内容保留 |

### Math 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MathRenderer.swift | 部分覆盖 | render() 异步边界 + 布局集成；JS 错误处理/pending 队列未测试 |

### UI/Components 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| AsyncTextView.swift | 部分覆盖 | nil string 处理；后台 Task/TextKit 2 绘制未测试 |
| AsyncCodeView.swift | 部分覆盖 | 子视图结构 + 布局；copy 按钮交互未测试 |
| AsyncImageView.swift | 部分覆盖 | 类型/nil/无效 URL 处理；实际下载/解码未测试 |

### UI/CollectionView 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| MarkdownCollectionViewCell.swift | 较好覆盖 | configure + prepareForReuse + 节点类型路由 (iOS) |
| MarkdownCollectionView_iOS.swift | 未直接覆盖 | DataSource/Delegate 需集成环境 |
| MarkdownCollectionView_macOS.swift | 部分覆盖 | 初始化 + ScrollView 子视图验证 |
| MarkdownItemView.swift | 较好覆盖 | loadView + configure + prepareForReuse + 代码块样式 + 回收 |

### Utils 模块

| 文件 | 覆盖状态 | 说明 |
|------|---------|------|
| PerformanceProfiler.swift | 较好覆盖 | 同步/异步测量 + Metric 枚举 |

---

## 剩余覆盖缺口

### P1 — 仍需关注

| 缺口 | 影响 | 涉及文件 |
|------|------|---------|
| AsyncImageView 实际加载 | 网络/本地图片下载与解码 | AsyncImageView.swift |
| MathRenderer 错误处理 | JS 执行失败路径 | MathRenderer.swift |
| CollectionView DataSource (iOS) | 数据源协议方法 | MarkdownCollectionView_iOS.swift |

### P2 — 质量提升

| 缺口 | 影响 | 涉及文件 |
|------|------|---------|
| AsyncTextView 绘制管道 | 后台 CoreGraphics 渲染 | AsyncTextView.swift |
| 多语言语法高亮 | 仅测试了 Swift | SplashHighlighter.swift |
| 性能基准测试 | 无可复现基准 | PerformanceProfiler.swift |

---

## 补全建议优先级

```
第一批 (P1): AsyncImageView 加载 + MathRenderer 错误处理 + iOS DataSource
第二批 (P2): AsyncTextView 绘制 + 多语言高亮 + 性能基准
```
