# Virtualized Rendering UI

## Overview
Phase 3 bridges the Asynchronous Layout Engine (Phase 2) to the actual hardware pixels.
Monolithic text or web views can make mounting and backing-store cost grow with document
content, so MarkdownKit instead virtualizes top-level layout results through collection views.

We solve this using **Collection View Virtualization** combined with **Texture (AsyncDisplayKit) Display States**.

## Architecture

1. **The Scroller (`MarkdownCollectionView`)**
   - We utilize `UICollectionView` (iOS) and `NSCollectionView` (macOS).
   - These Apple classes are highly optimized to only hold views in memory that are *currently visible* on the screen.
   - When scrolling, views that disappear off the top are instantly moved to the bottom to display new content.

2. **O(1) Sizing**
   - In standard iOS/macOS development, the collection view must calculate the size of every cell which triggers expensive TextKit math on the main thread.
   - Because our `LayoutSolver` already calculated everything on a background queue, our delegate simply returns `layout.size` in O(1) time. No math happens on the main thread.

3. **Asynchronous Backing Stores (`AsyncTextView`, `AsyncCodeView`)**
   - When a recycled view comes onscreen, `AsyncTextView` rasterizes its already-laid-out `NSAttributedString` into a `CGContext` off-main, then publishes `layer.contents` from UI context.
   - Inline image attachments participate in that same attributed-string rasterization. There is no image-specific cell route or top-level/block-image view.
   - `AsyncCodeView` composes the text backing store with its code-specific UI.

4. **Aggressive Purging**
   - Inside `prepareForReuse()`, views cancel background display work and clear layer contents.
   - This keeps steady-state memory usage tied to what's currently on/near screen rather than total document length, since off-screen backing stores are purged rather than retained. No fixed memory ceiling has been benchmarked or is guaranteed for arbitrarily large documents; separately, `MarkdownParser.ResourceLimits.maximumInputBytes` (default 1,048,576 UTF-8 bytes) bounds the input accepted by the parser itself.

## Inline Image Boundary

- Parser-produced images remain inline `ImageNode` values inside text-like layout.
- During layout, `ImageResourceLoader` alone resolves sources, applies `ImageLoadingPolicy`, rejects disallowed redirects before following them, and streams file/`URLSession` bytes under the policy cap before final-response validation. `ImageAttachmentBuilder` then uses ImageIO to decode an oriented, width-constrained thumbnail.
- The decoded attachment cache is keyed by policy/source/rounded target width, limited to 128 entries and 64 MiB total cost, with a hard 64 MiB decoded bound per image.
- Image loading is therefore layout-driven, not visibility-driven. Changing `imageLoadingPolicy` relayouts and rebuilds attachments rather than reconfiguring visible cells.
