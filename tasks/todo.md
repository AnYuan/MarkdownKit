# Implementation Checklist

## Setup
- [ ] Initialize Swift Package structure inside `MyMarkdown` workspace
- [ ] Add `swift-markdown` as a dependency

## Phase 1: Parsing Engine
- [ ] Define core AST node structure (e.g., `DocumentNode`, `BlockNode`, `InlineNode`)
- [ ] Implement `swift-markdown` Visitor to map to internal nodes
- [ ] Setup AST Middleware/Plugin architecture
- [ ] Add unit tests for AST parser against CommonMark / GFM 

## Phase 2: Layout Engine
- [ ] Create `LayoutResult` models holding frames and text representations
- [ ] Implement background thread text sizing using TextKit 2 logic
- [ ] Establish memory-safe chunking for massive document bounding-box resolution
- [ ] Add unit tests for Layout calculation and dynamic type scaling

## Phase 3: Rendering UI
- [ ] Implement virtualized scrolling container (`UICollectionView` / `NSTableView`)
- [ ] Create native UI components for different node types (Text, Image, CodeBlock)
- [ ] Implement async displaying (mount on visible, demount on hidden)
- [ ] Perform application memory profiling (Target: < 100MB parsing overhead)

## Phase 4: Extended Features
- [ ] Integrate syntax highlighting for code blocks (Splash / Custom)
- [ ] Add iOS/macOS native "Copy Code" button and language indicator overhead
- [ ] Integrate LaTeX math equations parser and view
- [ ] Build unified Typography and Color token system (Day / Night mode)

## Phase 5: Delivery
- [ ] Finalize automated UI snapshot testing
- [ ] Comprehensive Code review and documentation
- [ ] Verify scrolling FPS on extreme document sizes
