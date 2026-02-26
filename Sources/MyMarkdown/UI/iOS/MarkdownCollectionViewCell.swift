//
//  MarkdownCollectionViewCell.swift
//  MyMarkdown
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A highly reusable, recycled view cell managed by `UICollectionView`.
/// Its sole responsibility is mounting the pre-calculated `LayoutResult` 
/// and displaying the dynamically generated background `CGImage` or `CGContext` snapshots.
public class MarkdownCollectionViewCell: UICollectionViewCell {
    
    public static let reuseIdentifier = "MarkdownCollectionViewCell"
    
    /// The specific view container responsible for rendering the assigned AST element.
    private var hostedView: UIView?
    
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
        self.contentView.frame.size = layout.size
    }
}
#endif
