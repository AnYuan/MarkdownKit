# Implementation Checklist (Atomic Commits)

## Setup
- [x] Initialize standard Swift Package `MyMarkdown` workspace
- [x] Add Apple's `swift-markdown` library as a dependency
- [x] Setup base XCTest target `MyMarkdownTests`
- [x] Implement `PerformanceProfiler` utility for benchmarking AST and Layout speeds

## Phase 1: Parsing Engine (AST)
- [x] Define internal `MarkdownNode` protocol and base element structures
- [x] Implement `DocumentNode`, `BlockNode`, and `InlineNode` models
- [x] Implement `HeaderNode`, `ParagraphNode`, and `TextNode` models
- [x] Implement `CodeBlockNode` and `InlineCodeNode` models
- [x] Implement `MathNode` (block `$$` and inline `$`) models
- [x] Implement `ImageNode` and `LinkNode` models
- [x] Create `MarkupVisitor` class subscribing to `swift-markdown` API
- [x] Implement `MarkupVisitor` parsing for basic blocks (Headers, Paragraphs)
- [x] Implement `MarkupVisitor` parsing for complex blocks (Code, Images, Lists)
- [x] Implement AST Extensibility mechanism (Middleware Plugin protocol)
- [x] Add Unit Tests: CommonMark standard parsing fidelity
- [x] Add Unit Tests: GitHub Flavored Markdown parsing fidelity

## Phase 2: Asynchronous Layout Engine
- [x] Implement `TypographyToken` and `ColorToken` theme structures
- [x] Create `LayoutResult` models containing exact `CGRect` dimensions
- [x] Create base `TextKit 2` calculator class running on background queue
- [x] Implement background sizing solver for standard text blocks
- [x] Implement caching mechanism for Layout models based on width/Device scale
- [x] Implement asynchronous yielding logic for giant documents (>10MB)
- [x] Add Unit Tests: Verify exact framing dimension logic for varying strings

## Phase 3: Virtualized Rendering UI
- [x] Implement core virtualized `NSCollectionView` (macOS) layout
- [x] Implement core virtualized `UICollectionView` (iOS) layout
- [x] Create Native component: `MarkdownTextView`
- [x] Create Native component: `MarkdownImageView`
- [x] Create Native component: `MarkdownCodeView`
- [x] Implement `Texture`-style Display State logic: Asynchronously render text to `CGContext` on background thread
- [x] Implement `Texture`-style Display State logic: Asynchronously decode image data to `CGImage` on background thread
- [x] Implement `Texture`-style Display State logic: Mount views onto main thread only when visible
- [x] Implement `Texture`-style Display State logic: Purge memory-heavy backing stores when offscreen
- [/] Add Unit Tests: Verify node virtualization limits memory consumption

## Phase 4: Extended Features (ChatGPT Parity)
- [x] Integrate native "Copy Paste" UX for Code Blocks
- [x] Integrate lightweight syntax highlighter for Code Blocks
- [x] Add UI styling for Markdown Tables and Checkbox Task Lists
- [x] Integrate lightweight LaTeX renderer (MathJax/iosMath) for $$ MathNodes
- [x] Implement smooth transitioning between Light/Dark mode themes
- [x] Add UI Snapshot Tests for Code Block and Math rendering parity (Substituted by Unit Tests due to missing Host App)

## Phase 5: Delivery & Polish
- [x] Profile and resolve any memory leaks associated with image loading or TextKit caches (Demo App `MyMarkdownDemo` Provided)
- [x] Profile and resolve scrolling hitches using Instruments (Demo App `MyMarkdownDemo` Provided)
- [x] Final architecture documentation and code hygiene review

## Phase 6: GitHub Advanced Formatting Alignment (PRD §7)

### P0: Core Markdown Rendering Parity
- [x] Switch table rendering from text emulation to native `NSTextTable` / `NSTextTableBlock`
- [x] Apply GitHub-like table styling baseline (header fill, borders, zebra stripe body rows)
- [x] Keep column alignment mapping parity for GFM tables (`left/center/right`)
- [x] Add parser/layout support for fenced math blocks using ```math syntax
- [x] Add strict regression tests for inline `$...$` and block `$$...$$` edge cases (escaping, multiline, mixed text)
- [x] Add optional language badge rendering for fenced code blocks

### P1: Advanced Formatting Features
- [x] Implement `<details>/<summary>` parsing as dedicated nodes (instead of raw `InlineHTML` fallback)
- [x] Render collapsible sections natively in both iOS/macOS UI layers
- [x] Add diagram block detection for fenced languages: `mermaid`, `geojson`, `topojson`, `stl`
- [x] Implement pluggable diagram rendering adapters with code-block fallback when adapter is unavailable
- [ ] Extend autolink support from URLs to issue/PR refs, commit SHAs, and `@mention` tokens (resolver-based)
- [ ] Upgrade tasklist rendering to support editor-mode interaction toggles while preserving read-only mode

### P2: Host-App Integration Boundaries
- [ ] Expose extension APIs for attachment workflows (upload + insertion), kept out of renderer core
- [ ] Expose extension APIs for permalink/snippet cards (repository context required)
- [ ] Expose extension hooks for issue-keyword semantics (`close/fix/resolve`) for host products

### Cross-Cutting Test Tasks
- [ ] Add snapshot coverage for table, code, math, and tasklist visual parity on iOS + macOS
- [ ] Add feature-status matrix test docs linking each PRD §7 feature to test case names
