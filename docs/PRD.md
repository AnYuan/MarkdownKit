# Product Requirements Document (PRD): High-Performance Markdown Renderer

## 1. Overview
The goal of this project is to implement the **best-in-class Markdown renderer** for macOS and iOS platforms. It aims to provide unparalleled performance—handling exceptionally large Markdown files with zero UI freezing—and offer a comprehensive set of features expected from modern Markdown editors. 

The renderer will native Swift and modern Apple frameworks (TextKit 2 / SwiftUI) to ensure that it feels completely native, lightweight, and highly responsive.

## 2. Competitive Landscape & Research
We analyzed several leading open-source Markdown renderers in the Apple ecosystem to understand the current state-of-the-art:

- **Down**: Built upon `cmark`. Extremely fast due to its C-foundation. Capable of rendering large documents in milliseconds.
- **Ink**: A fast, native Swift parser by John Sundell. It avoids heavy regular expressions and minimizes string copying for near O(N) complexity.
- **Swift Markdown**: Apple's official Swift package built on `cmark-gfm`. It provides robust GitHub Flavored Markdown (GFM) support and an Abstract Syntax Tree (AST) for deeper analysis.
- **MarkdownUI / Textual**: Great for SwiftUI native declarative UI rendering, but can struggle with massive, multi-megabyte Markdown files if not highly optimized.

**Takeaways**: To achieve the _best performance_, we must leverage a highly optimized C-based parser like `cmark-gfm` (or Apple's `swift-markdown`) to generate the AST asynchronously, and then map that AST directly into native Apple UI text components (TextKit 2 / CoreText) without relying on WebViews (which consume excessive memory and loading time).

## 3. Core Features

### 3.1. Markdown Standard Support (ChatGPT App Parity)
The renderer must support the exact Markdown syntax subset utilized by the official ChatGPT mobile and desktop apps. This guarantees users receive a familiar and expected parsing behavior.
- **Full CommonMark Compliance**: Accurate parsing of standard Markdown.
- **GitHub Flavored Markdown (GFM)**: 
  - Tables
  - Task lists (interactive checkboxes)
  - Strikethrough
  - Autolinks

### 3.2. Extended Syntax & Rich Media (ChatGPT App Parity)
- **Rich Code Blocks**: Full syntax highlighting for all standard programming languages outputted by LLMs, complete with a "Copy Code" button and language label.
- **Complex Math & Equations**: Robust LaTeX syntax support (`$$` for block and `$` for inline syntax) to elegantly display complex mathematical equations, matrices, and theorems (achieved natively or using high-performance bridging via KaTeX/MathJax).
- **Headers & Typography**: Scaling header sizes (`#` to `######`), blockquotes (`>`), and bold/italic nested rendering precisely as seen in ChatGPT.
- **Image Handling**: Asynchronous loading and caching of remote and local images.
- **Frontmatter Parsing**: Support for YAML/TOML frontmatter parsing and display.
- **Footnotes & Citations**: Anchor links jumping seamlessly within the document.

### 3.3. Customizability & Extensibility
- **Syntax Extensibility**: The parsing and rendering pipeline must be extensible, allowing developers to inject custom rules (via AST modifiers or a plugin system) to support new, non-standard Markdown syntax natively.
- **Theming System**: Deeply customizable typography, colors, and layout configurations.
- **Dynamic Type Support**: Accessibility-ready out of the box.
- **Day / Night Mode**: Automatic, elegant transitioning between iOS/macOS light and dark appearances.

## 4. Performance Requirements

"Even opened with a huge markdown file, we should still have best performance."

1. **Zero UI Blocking**: 
   - Parsing the document into an AST must occur on a background thread.
   - For giant files (e.g., millions of words), parsing should be chunked or yielded so memory doesn't spike.
2. **Lazy, Asynchronous Layout (TextureKit Inspired)**:
   - Inspired by the open-source TextureKit / AsyncDisplayKit framework pattern, sizing and text layout calculation (e.g., measuring bounding boxes for string attributes) must be performed **asynchronously on background threads**.
   - Only the visible text and elements (images, code blocks) in the scroll view should be fully rendered and instantiated into views lazily. Content waiting off-screen is stored simply as layout models.
   - We will utilize `TextKit 2` with non-contiguous layout or `UICollectionView` / `NSTableView` logic to achieve O(1) rendering time relative to file size.
3. **60 / 120 FPS Scrolling**: 
   - Scroll performance must be buttery smooth. Heavy operations like syntax highlighting code blocks must be debounced and executed asynchronously.
4. **Memory Efficiency**:
   - AST nodes should be dropped or highly compressed if off-screen in massive documents, relying on virtualized ranges. Memory footprint must stay below 100MB even for 10MB+ Markdown strings.
5. **In-Built Performance Benchmarking**:
   - The framework must expose a `PerformanceProfiler` API to statically measure and log precisely how many milliseconds the AST parsing and Layout generations took, ensuring transparency for developers using the library.

## 5. Technical Stack

- **Platform**: iOS 17.0+, macOS 26.0+
- **Language**: Swift 6.0+
- **Parser Foundation**: `swift-markdown` (Apple's wrapper around `cmark-gfm`) for the most reliable and fastest AST generation.
- **UI Framework**: UIKit on iOS (`UITextView`, `UICollectionView`) combined with `TextKit 2` for ultimate text performance. (AppKit on macOS).
- **Architecture**: 
  - A declarative wrapper around asynchronous layout calculation to emulate the TextureKit strategy of never blocking the main thread during heavy text typesetting.
  - A middleware/plugin system operating on the Abstract Syntax Tree (AST) generated by `swift-markdown`, enabling intercepting and rewriting of nodes (e.g., custom tags, directives) before the UI layout phase.

## 6. Quality Assurance & Testing

- **Test Coverage**: The project demands the highest level of stability. We aim for **near 100% test coverage** across the codebase.
- **Unit Testing**: Comprehensive XCTest suites for all AST parsing logic, layout calculation engines, and text attribute generation. 
- **UI/Snapshot Testing**: Automated UI tests and snapshot tests for the rendering layer to ensure zero visual regressions across both iOS and macOS platforms when rendering complex Markdown features (like deeply nested lists or LaTeX equations).
