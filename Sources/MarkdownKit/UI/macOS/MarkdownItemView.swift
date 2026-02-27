//
//  MarkdownItemView.swift
//  MarkdownKit
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

private final class DetailsTextView: NSTextView {
    var summaryCharacterRange: NSRange = NSRange(location: NSNotFound, length: 0)
    var onSummaryClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if didClickSummary(with: event) {
            onSummaryClick?()
            return
        }
        super.mouseDown(with: event)
    }

    private func didClickSummary(with event: NSEvent) -> Bool {
        guard summaryCharacterRange.location != NSNotFound,
              summaryCharacterRange.length > 0,
              let layoutManager,
              let textContainer else {
            return false
        }

        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerInset.width
        point.y -= textContainerInset.height

        guard layoutManager.usedRect(for: textContainer).contains(point) else {
            return false
        }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return NSLocationInRange(characterIndex, summaryCharacterRange)
    }
}

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

    public func configure(with layout: LayoutResult, onToggleDetails: ((DetailsNode) -> Void)? = nil) {
        hostedView?.removeFromSuperview()
        hostedView = nil

        self.view.frame.size = layout.size

        guard let attrString = layout.attributedString, attrString.length > 0 else { return }

        // Use NSTextView for proper multi-line rich text rendering.
        let textView: NSTextView
        if let details = layout.node as? DetailsNode {
            let detailsView = DetailsTextView(frame: NSRect(origin: .zero, size: layout.size))
            detailsView.summaryCharacterRange = detailsSummaryRange(in: attrString.string)
            detailsView.onSummaryClick = { onToggleDetails?(details) }
            textView = detailsView
        } else {
            textView = NSTextView(frame: NSRect(origin: .zero, size: layout.size))
        }

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        // Replace text storage content with our pre-styled attributed string
        textView.textStorage?.setAttributedString(attrString)

        // Code blocks get background + rounded corners
        if layout.node is CodeBlockNode || layout.node is DiagramNode {
            textView.drawsBackground = true
            textView.backgroundColor = NSColor.controlBackgroundColor
            textView.wantsLayer = true
            textView.layer?.cornerRadius = 6
            textView.textContainerInset = NSSize(width: 8, height: 8)
        }

        view.addSubview(textView)
        hostedView = textView
    }

    private func detailsSummaryRange(in text: String) -> NSRange {
        let nsText = text as NSString
        let newlineRange = nsText.range(of: "\n")
        let end = newlineRange.location == NSNotFound ? nsText.length : newlineRange.location
        guard end > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: end)
    }
}
#endif
