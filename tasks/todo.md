# Implementation Checklist (Atomic Commits)

## Setup
- [x] Initialize standard Swift Package `MyMarkdown` workspace
- [x] Add Apple's `swift-markdown` library as a dependency
- [x] Setup base XCTest target `MyMarkdownTests`
- [x] Implement `PerformanceProfiler` utility for benchmarking AST and Layout speeds

## Phase 1: Parsing Engine (AST)
- [ ] Define internal `MarkdownNode` protocol and base element structures
- [ ] Implement `DocumentNode`, `BlockNode`, and `InlineNode` models
- [ ] Implement `HeaderNode`, `ParagraphNode`, and `TextNode` models
- [ ] Implement `CodeBlockNode` and `InlineCodeNode` models
- [ ] Implement `MathNode` (block `$$` and inline `$`) models
- [ ] Implement `ImageNode` and `LinkNode` models
- [ ] Create `MarkupVisitor` class subscribing to `swift-markdown` API
- [ ] Implement `MarkupVisitor` parsing for basic blocks (Headers, Paragraphs)
- [ ] Implement `MarkupVisitor` parsing for complex blocks (Code, Images, Lists)
- [ ] Implement AST Extensibility mechanism (Middleware Plugin protocol)
- [ ] Add Unit Tests: CommonMark standard parsing fidelity
- [ ] Add Unit Tests: GitHub Flavored Markdown parsing fidelity

## Phase 2: Asynchronous Layout Engine
- [ ] Implement `TypographyToken` and `ColorToken` theme structures
- [ ] Create `LayoutResult` models containing exact `CGRect` dimensions
- [ ] Create base `TextKit 2` calculator class running on background queue
- [ ] Implement background sizing solver for standard text blocks
- [ ] Implement caching mechanism for Layout models based on width/Device scale
- [ ] Implement asynchronous yielding logic for giant documents (>10MB)
- [ ] Add Unit Tests: Verify exact framing dimension logic for varying strings

## Phase 3: Virtualized Rendering UI
- [ ] Implement core virtualized `NSCollectionView` (macOS) layout
- [ ] Implement core virtualized `UICollectionView` (iOS) layout
- [ ] Create Native component: `MarkdownTextView`
- [ ] Create Native component: `MarkdownImageView`
- [ ] Create Native component: `MarkdownCodeView`
- [ ] Implement `Texture`-style Display State logic: Mount views only when visible
- [ ] Implement `Texture`-style Display State logic: Purge views when offscreen
- [ ] Add Unit Tests: Verify node virtualization limits memory consumption

## Phase 4: Extended Features (ChatGPT Parity)
- [ ] Integrate native "Copy Paste" UX for Code Blocks
- [ ] Integrate lightweight syntax highlighter for Code Blocks
- [ ] Add UI styling for Markdown Tables and Checkbox Task Lists
- [ ] Integrate lightweight LaTeX renderer (MathJax/iosMath) for $$ MathNodes
- [ ] Implement smooth transitioning between Light/Dark mode themes
- [ ] Add UI Snapshot Tests for Code Block and Math rendering parity

## Phase 5: Delivery & Polish
- [ ] Profile and resolve any memory leaks associated with image loading or TextKit caches
- [ ] Profile and resolve scrolling hitches using Instruments
- [ ] Final architecture documentation and code hygiene review
