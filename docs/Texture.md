# Texture (AsyncDisplayKit) Architecture & Learnings

## Overview
[Texture](https://github.com/TextureGroup/Texture) (formerly AsyncDisplayKit by Facebook/Pinterest) is an iOS framework designed to keep even the most complex user interfaces smooth and responsive. It achieves a consistent 60 FPS (or 120 FPS on ProMotion) by shifting expensive UI operations—such as text sizing, image decoding, and view layout—off the main thread.

## Core Concepts

### 1. `ASDisplayNode`
The fundamental building block of Texture. 
- It is a thread-safe abstraction over `UIView` and `CALayer`.
- Unlike `UIView`, which can only be safely instantiated and configured on the main thread, `ASDisplayNode` can be created and fully configured on background queues.
- Nodes lazily generate their underlying views/layers only when they are about to become visible on-screen.

### 2. Asynchronous Layout Engine (`ASLayoutSpec`)
Texture moves away from Auto Layout engines (which block the main thread) and utilizes a declarative, FlexBox-inspired layout engine.
- Layouts are defined using `ASLayoutSpec`, which are immutable objects describing the structure of nodes.
- When the screen needs to be drawn, Texture computes the sizing and frames of the entire sub-hierarchy asynchronously on a background thread.
- Only the final, pre-calculated frames are applied to the UI elements on the main thread.

### 3. Intelligent Preloading & Intelligent Visibility
Texture manages the lifecycle of nodes based on their proximity to the visible screen area (viewport).
- **Preload State**: The node starts gathering data (e.g., fetching a remote image or parsing Markdown).
- **Display State**: The node asynchronously draws its contents into a backing store (e.g., text rendering into a `CGContext`).
- **Visible State**: The underlying `UIView` or `CALayer` is mounted and displayed to the user.
- When an element scrolls far off-screen, Texture automatically purges memory-heavy backing stores (like decoded images or drawn text contexts) while keeping the layout model intact.

---

## Application to our High-Performance Markdown Renderer

To achieve the "best performance" for massive Markdown files, we will adopt the architectural philosophies of Texture into our Swift renderer:

### A. Background Layout & Sizing
- **The Problem**: A 5MB Markdown file contains tens of thousands of text blocks. Calling `NSAttributedString.boundingRect(with:...)` or configuring `TextKit` layouts on the main thread will instantly freeze the app.
- **The Texture Solution**: We will parse the AST and calculate the text layout (sizing blocks, handling line wrapping, resolving image dimensions) entirely on a background thread. The view layer will receive a pre-calculated model containing exact `{x, y, width, height}` rects.

### B. View/Layer Virtualization (The Node Pattern)
- We will not create a single massive `UITextView`.
- Instead, the Markdown document will be conceptually split into "Nodes" (e.g., ParagraphNode, CodeBlockNode, ImageNode).
- These models will be managed by a high-performance recycling `UICollectionView` (or a custom virtualized scroll view). View components will only be instantiated (mounted) just before they enter the screen, identical to Texture's visibility states.

### C. Asynchronous Text Drawing
- Heavy operations like syntax highlighting code blocks or rendering LaTeX will be scheduled on background queues. 
- While scrolling, placeholder frames or un-highlighted text can be shown instantly, with the heavy rendering popping in asynchronously without dropping a single frame of scroll performance.
