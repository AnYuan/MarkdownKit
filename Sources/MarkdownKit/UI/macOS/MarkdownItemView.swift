//
//  MarkdownItemView.swift
//  MarkdownKit
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

private final class InteractiveTextView: NSTextView {
    var summaryCharacterRange: NSRange = NSRange(location: NSNotFound, length: 0)
    var onSummaryClick: (() -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            super.mouseDown(with: event)
            return
        }
        
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerInset.width
        point.y -= textContainerInset.height
        
        guard layoutManager.usedRect(for: textContainer).contains(point) else {
            super.mouseDown(with: event)
            return
        }
        
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        
        // 1. Details summary toggle
        if summaryCharacterRange.location != NSNotFound, NSLocationInRange(characterIndex, summaryCharacterRange) {
            onSummaryClick?()
            return
        }
        
        // 2. Interactive checklists
        if characterIndex < textStorage?.length ?? 0 {
            if let interactionData = textStorage?.attribute(.markdownCheckbox, at: characterIndex, effectiveRange: nil) as? CheckboxInteractionData {
                onCheckboxToggle?(interactionData)
                return
            }
        }
        
        super.mouseDown(with: event)
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

    public func configure(
        with layout: LayoutResult,
        onToggleDetails: ((DetailsNode) -> Void)? = nil,
        onCheckboxToggle: ((CheckboxInteractionData) -> Void)? = nil
    ) {
        hostedView?.removeFromSuperview()
        hostedView = nil

        self.view.frame.size = layout.size

        guard let attrString = layout.attributedString, attrString.length > 0 else { return }

        // Use InteractiveTextView for proper multi-line rich text rendering and interaction.
        let textView = InteractiveTextView(frame: NSRect(origin: .zero, size: layout.size))
        textView.onCheckboxToggle = onCheckboxToggle
        
        if let details = layout.node as? DetailsNode {
            textView.summaryCharacterRange = detailsSummaryRange(in: attrString.string)
            textView.onSummaryClick = { onToggleDetails?(details) }
        }

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        // Replace text storage content with our pre-styled attributed string
        textView.textStorage?.setAttributedString(attrString)

        // Handle NSAccessibility for the textView
        textView.setAccessibilityElement(true)
        if layout.node is CodeBlockNode || layout.node is DiagramNode {
            textView.drawsBackground = true
            textView.backgroundColor = NSColor.controlBackgroundColor
            textView.wantsLayer = true
            textView.layer?.cornerRadius = 6
            textView.textContainerInset = NSSize(width: 8, height: 8)
            textView.setAccessibilityRole(.group)
            textView.setAccessibilityLabel("Code Block")
            textView.setAccessibilityValue(attrString.string)
        } else if layout.node is TableNode {
            textView.setAccessibilityRole(.group)
            textView.setAccessibilityLabel("Table")
        } else if let details = layout.node as? DetailsNode {
            textView.setAccessibilityRole(.button)
            textView.setAccessibilityLabel("Collapsible Section")
            textView.setAccessibilityValue(details.isOpen ? "Expanded" : "Collapsed")
        } else if layout.node is MathNode {
            textView.setAccessibilityRole(.staticText)
            textView.setAccessibilityLabel("Math Equation")
            textView.setAccessibilityValue((layout.node as? MathNode)?.equation)
        } else {
            // General paragraphs and text
            textView.setAccessibilityRole(.staticText)
            
            // Check if it's a task list item
            var isTask = false
            var isChecked = false
            attrString.enumerateAttribute(.markdownCheckbox, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, stop in
                if let data = value as? CheckboxInteractionData {
                    isTask = true
                    isChecked = data.isChecked
                    stop.pointee = true
                }
            }
            if isTask {
                textView.setAccessibilityRole(.checkBox)
                textView.setAccessibilityValue(isChecked ? 1 : 0)
            }
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
