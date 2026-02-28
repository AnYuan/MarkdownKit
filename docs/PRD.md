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
- **Diagrams & Flowcharts**: Native rendering of `mermaid` diagrams via a pluggable adapter, providing rich visualizations.
- **Frontmatter Parsing**: Support for YAML/TOML frontmatter parsing and display.
- **Footnotes & Citations**: Anchor links jumping seamlessly within the document.

### 3.3. Customizability & Extensibility
- **Syntax Extensibility**: The parsing and rendering pipeline must be extensible, allowing developers to inject custom rules (via AST modifiers or a plugin system) to support new, non-standard Markdown syntax natively.
- **Theming System**: Deeply customizable typography, colors, and layout configurations.
- **Dynamic Type Support**: Accessibility-ready out of the box.
- **Day / Night Mode**: Automatic, elegant transitioning between iOS/macOS light and dark appearances.
- **Accessibility & VoiceOver**: Deep integration with `UIAccessibilityElement` and `NSAccessibilityElement` to ensure the highly customized virtualized text rendering remains fully navigable and readable by screen readers.

### 3.4. Security & Robustness (Production-Grade)
To ensure the renderer is safe for use in production environments with untrusted user-generated content, it must enforce the following constraints:
- **URL Sanitization**: Strict filtering of potentially dangerous URI schemes (e.g., `javascript:`, `vbscript:`) in links and images to prevent Cross-Site Scripting (XSS). Only allow-listed protocols (such as `http`, `https`, `mailto`) should output actionable URLs by default.
- **Deep Nesting Defense**: Implementation of a maximum AST recursion depth (e.g., 50-100 levels) during both the parsing and layout phases. This prevents Stack Overflow crashes and Denial of Service (DoS) attacks caused by exponentially nested markdown structures (like unclosed blockquotes or lists).
- **Crash Resilience**: The parsing, layout, and rendering pipelines must be engineered to never `fatalError` or crash when fed severely malformed inputs.

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
- **Fuzz Testing**: Deterministic fuzz testing and pathological payload rendering suites. The Markdown string input must be robustly tested against randomly permuted garbage and hostile nesting structures to ensure a zero-crash guarantee.
- **UI/Snapshot Testing**: Automated snapshot tests for the rendering layer (e.g., using `swift-snapshot-testing`) to ensure zero visual regressions across both iOS and macOS platforms when rendering complex Markdown features (like deeply nested lists or LaTeX equations).
- **Comprehensive Documentation**: Generation of complete API and architecture documentation using Apple's `DocC` to facilitate easy integration by host apps.

### 6.1 Automated Syntax Verification Strategy (Primary Gate)
Manual page-by-page checking is not acceptable as the main validation method. The renderer must provide automated verification that covers all supported syntax families and high-risk regressions.

Required automated coverage dimensions:
1. **Syntax matrix coverage**: headers, emphasis, links, images, inline code, code blocks, lists, task lists, tables, math, blockquote, details, diagrams.
2. **Layout width matrix**: each syntax fixture validated across narrow, medium, and wide container widths.
3. **State and fallback coverage**: open and closed details, diagram adapter fallback, image load success and fallback, table alignment and wrapping behavior.
4. **Plugin pipeline coverage**: feature combinations validated with active plugin chains (details, diagrams, math).
5. **Stress coverage**: mixed-syntax permutation runs to detect crashers, pathological sizing, and unstable formatting paths.

### 6.2 Test Types and Ownership
1. **Syntax Fixture Tests** (unit/integration): assert AST shape, node counts, and expected semantic transforms.
2. **Layout Invariant Tests** (integration): assert finite geometry, stable top-level layout counts, attachment presence rules, and table readability constraints.
3. **Regression Tests for Known Bugs**: explicit tests for previously fixed issues (details toggle state, table column collapse, image fallback rendering, diagram fallback rendering, inline code visual tokenization).
4. **Optional Visual Snapshots** (platform-specific): for high-value visual blocks (tables, code, math, details).
5. **Stress and Fuzz-like Tests**: deterministic permutation suites that run in CI and fail on crashes or invalid geometry.

### 6.3 CI Quality Gates
The following must pass before merge:
1. `swift test` full suite.
2. Syntax matrix suite across width matrix.
3. Regression suite for known rendering bugs.
4. Stress suite for mixed syntax permutations.

Operational constraints:
1. Default tests must not rely on external network availability.
2. Fixture tests must be deterministic and reproducible on local machines and CI runners.
3. Every newly supported syntax feature must add at least one positive test and one fallback or error-path test.

## 7. GitHub Advanced Formatting Parity (Source of Truth)

This section defines parity targets based on GitHub Docs:
- Working with advanced formatting: <https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting>
- Organizing information with collapsed sections
- Creating and highlighting code blocks
- Creating diagrams
- About tasklists
- Organizing information with tables
- Writing mathematical expressions
- Autolinked references and URLs
- Attaching files
- Creating a permanent link to a code snippet
- Using keywords in issues and pull requests

### 7.1. Feature Matrix (Syntax + Rendering + Scope)

| Feature | Syntax/Behavior from GitHub Docs | Rendering Requirements in MarkdownKit | Scope |
|---|---|---|---|
| Collapsed sections | `<details><summary>Title</summary> ... </details>` and a blank line after `</summary>` | Render a collapsible block with summary row + disclosure state, preserving markdown content inside | In scope |
| Code blocks | Triple backticks fenced blocks, optional language identifier, 4-space indented blocks, nested fences supported via quadruple backticks | Monospace, syntax-highlighted block, border/background, copy button, optional language chip | In scope |
| Diagrams | Fenced block language identifiers: `mermaid`, `geojson`, `topojson`, `stl` | Detect diagram fences and render native diagram/preview components with fallback to code block when unsupported | In scope (iterative) |
| Tasklists | `- [ ]` and `- [x]`, nested tasklists, completion reflects checked items | Checkbox list visuals with proper spacing/indentation; optional interactive toggling in editor mode | In scope |
| Tables | Pipe + hyphen header syntax, optional edge pipes, blank line before table, alignment markers (`:---`, `:---:`, `---:`) | Native table cell borders, header emphasis/background, alternating row shading, alignment mapping | In scope |
| Math expressions | Inline `$...$`, block `$$...$$`, and fenced ```math``` | Inline math baseline alignment, block math display mode, deterministic glyph sizing, graceful fallback | In scope |
| Autolinks | URLs auto-link; issue/PR refs, labels, commit SHAs, mentions, custom autolinks in supported contexts | Convert supported tokens to tappable links with visual style parity and safe fallback for unknown refs | Partial (URL links done, reference linking pending) |
| Attaching files | GitHub comment editor feature with context-specific supported file types | Not a markdown rendering concern; editor/upload integration belongs to host app layer | Out of renderer scope |
| Permanent links to code | GitHub code UI action and snippet permalink behavior | Not a markdown parser/layout concern; host app integration only | Out of renderer scope |
| Issue/PR keywords | Workflow keywords like `close(s)`, `fix(es)`, `resolve(s)` | Not renderer scope; semantic workflow integration belongs to GitHub backend layer | Out of renderer scope |

### 7.2. Visual Style Baseline (GitHub-like)

For markdown-rendered blocks, style must approximate GitHub documentation visuals:
1. Table: subtle grid borders, bold header row, header fill, zebra-striping for alternate body rows.
2. Code: monospaced font, syntax colors, neutral background, low-contrast border radius.
3. Inline code: compact pill-like background with preserved baseline rhythm.
4. Math: inline formulas vertically centered relative to surrounding text; block formulas separated by block spacing.
5. Tasklists: checkbox icon + text baseline alignment, nested indentation consistent with list hierarchy.
6. Links/autolinks: clear hyperlink color and underline/accessibility affordance.

### 7.3. Context-Specific Constraints from GitHub Docs

1. Some features are only active in specific GitHub contexts (issues, pull requests, discussions, wiki, files with `.md` extension).
2. Renderer should implement syntax and visuals consistently, but platform workflow semantics (closing issues, attachments upload pipeline, permalink generation) remain host-app responsibilities.
3. When behavior is context-dependent, MarkdownKit must expose extension hooks rather than hardcode GitHub backend semantics.

### 7.4. Acceptance Criteria for Parity

1. Every "In scope" feature above has:
   - parser coverage (AST tests),
   - layout/render coverage (unit tests + snapshot where feasible),
   - explicit fallback behavior.
2. Visual regressions for table/code/math/tasklist are guarded by tests.
3. Feature-level docs stay synchronized with implementation status in `tasks/todo.md`.
