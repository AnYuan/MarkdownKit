//
//  MarkdownItemView.swift
//  MyMarkdown
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

/// A highly reusable, recycled view cell managed by `NSCollectionView`.
public class MarkdownItemView: NSCollectionViewItem {

    public static let reuseIdentifier = NSUserInterfaceItemIdentifier("MarkdownItemView")

    private var hostedView: NSView?

    public override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    public func configure(with layout: LayoutResult) {
        hostedView?.removeFromSuperview()
        hostedView = nil

        self.view.frame.size = layout.size

        guard let attrString = layout.attributedString, attrString.length > 0 else { return }

        // Use NSTextView for proper multi-line rich text rendering
        let textView = NSTextView(frame: NSRect(origin: .zero, size: layout.size))
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        // Replace text storage content with our pre-styled attributed string
        textView.textStorage?.setAttributedString(attrString)

        // Code blocks get background + rounded corners
        if layout.node is CodeBlockNode {
            textView.drawsBackground = true
            textView.backgroundColor = NSColor.controlBackgroundColor
            textView.wantsLayer = true
            textView.layer?.cornerRadius = 6
            textView.textContainerInset = NSSize(width: 8, height: 8)
        }

        view.addSubview(textView)
        hostedView = textView
    }
}
#endif
