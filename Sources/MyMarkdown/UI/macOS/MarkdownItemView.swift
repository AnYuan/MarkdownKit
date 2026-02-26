//
//  MarkdownItemView.swift
//  MyMarkdown
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// A highly reusable, recycled view cell managed by `NSCollectionView`.
/// Its sole responsibility is mounting the pre-calculated `LayoutResult` 
/// and displaying the dynamically generated background `CGImage` or `CGContext` snapshots.
public class MarkdownItemView: NSCollectionViewItem {
    
    public static let reuseIdentifier = NSUserInterfaceItemIdentifier("MarkdownItemView")
    
    /// The specific view container responsible for rendering the assigned AST element.
    private var hostedView: NSView?
    
    public override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
    }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        // Texture principle: aggressively purge backing stores and views when offscreen
        hostedView?.removeFromSuperview()
        hostedView = nil
    }
    
    /// Mounts the pre-calculated `LayoutResult` onto the main thread.
    public func configure(with layout: LayoutResult) {
        // Implementation for routing LayoutResult to the correct Subview (MarkdownTextView, ImageView, etc.)
        // will go here next. For now, we simply apply the exact frame.
        self.view.frame.size = layout.size
    }
}
#endif
