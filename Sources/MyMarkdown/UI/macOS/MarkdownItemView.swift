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
        hostedView?.removeFromSuperview()
        hostedView = nil

        self.view.frame.size = layout.size

        guard let attrString = layout.attributedString, attrString.length > 0 else { return }

        let textField = NSTextField(frame: NSRect(origin: .zero, size: layout.size))
        textField.attributedStringValue = attrString
        textField.isEditable = false
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byWordWrapping
        textField.preferredMaxLayoutWidth = layout.size.width

        // For code blocks, add a subtle background
        if layout.node is CodeBlockNode {
            textField.drawsBackground = true
            textField.backgroundColor = NSColor.controlBackgroundColor
            textField.wantsLayer = true
            textField.layer?.cornerRadius = 6
        }

        view.addSubview(textField)
        hostedView = textField
    }
}
#endif
