# Virtualized Rendering UI

## Overview
Phase 3 bridges the Asynchronous Layout Engine (Phase 2) to the actual hardware pixels. The core problem `MyMarkdown` solves is typical Markdown renderers use giant `UITextView` or `WKWebView` containers. When a document has 200,000 words or 50 images, these monolithic views consume hundreds of megabytes of RAM and lock up the main thread during rendering.

We solve this using **Collection View Virtualization** combined with **Texture (AsyncDisplayKit) Display States**.

## Architecture

1. **The Scroller (`MarkdownCollectionView`)**
   - We utilize `UICollectionView` (iOS) and `NSCollectionView` (macOS).
   - These Apple classes are highly optimized to only hold views in memory that are *currently visible* on the screen.
   - When scrolling, views that disappear off the top are instantly moved to the bottom to display new content.

2. **O(1) Sizing**
   - In standard iOS/macOS development, the collection view must calculate the size of every cell which triggers expensive TextKit math on the main thread.
   - Because our `LayoutSolver` already calculated everything on a background queue, our delegate simply returns `layout.size` in O(1) time. No math happens on the main thread.

3. **Asynchronous Backing Stores (`AsyncTextView`, `AsyncImageView`, `AsyncCodeView`)**
   - When a recycled view comes onscreen, we do **not** use `UILabel` or `UIImageView`.
   - Instead, we dispatch a new `Task.detached` to a background CPU core.
   - For text: We draw the `NSAttributedString` into a raw `CGContext` canvas.
   - For images: We download the image, downsample it to the exact bounding box, and decode the pixels entirely in the background.
   - Finally, we jump back to the `MainActor` and set the `view.layer.contents = cgImage`.

4. **Aggressive Purging**
   - Inside `prepareForReuse()`, we immediately nullify background tasks and layer contents.
   - This ensures memory usage remains completely flat (typically under 20MB) no matter if the Markdown file is 10 lines or 10,000,000 lines long.
