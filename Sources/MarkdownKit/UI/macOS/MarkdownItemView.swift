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
    var onLinkTap: ((URL) -> Void)?
    private var projectedAccessibilityValue: Any?

    func setProjectedAccessibilityValue(_ value: PlatformAccessibility.AppKitValue?) {
        switch value {
        case let .text(text):
            projectedAccessibilityValue = text
        case let .number(number):
            projectedAccessibilityValue = NSNumber(value: number)
        case nil:
            projectedAccessibilityValue = nil
        }
    }

    // NSTextView narrows this Objective-C API to String? in Swift, while
    // NSAccessibility permits NSNumber for checkbox values.
    @objc(accessibilityValue)
    func projectedAccessibilityValueForAppKit() -> Any? {
        projectedAccessibilityValue
    }

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

        // 3. Link taps
        if characterIndex < textStorage?.length ?? 0 {
            if let url = textStorage?.attribute(.link, at: characterIndex, effectiveRange: nil) as? URL {
                onLinkTap?(url)
                return
            }
        }

        super.mouseDown(with: event)
    }
}

/// A highly reusable, recycled view cell managed by `NSCollectionView`.
class MarkdownItemView: NSCollectionViewItem {

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("MarkdownItemView")

    private var hostedView: InteractiveTextView?
    var preferredContainerWidth: CGFloat?
    var textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly

    override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        
        // Initialize once to enable NSCollectionView recycling
        let textView = InteractiveTextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.drawsBackground = false
        textView.minSize = .zero
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.autoresizingMask = [.width, .height]
        
        self.view.addSubview(textView)
        self.hostedView = textView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let textView = hostedView {
            resetNonTextState(textView)
            clearText(in: textView)
            textView.isSelectable = false
        }
        preferredContainerWidth = nil
    }

    func configure(
        with layout: LayoutResult,
        theme: Theme = .default,
        textInteractionMode: MarkdownTextInteractionMode = .asyncReadOnly,
        onToggleDetails: ((DetailsNode) -> Void)? = nil,
        onCheckboxToggle: ((CheckboxInteractionData) -> Void)? = nil,
        onLinkTap: ((URL) -> Void)? = nil
    ) {
        guard let textView = hostedView else { return }

        self.textInteractionMode = textInteractionMode
        textView.isSelectable = textInteractionMode == .selectableNative

        let containerWidth = preferredContainerWidth
            ?? (view.bounds.width > 0 ? view.bounds.width : layout.size.width)

        view.frame.size = NSSize(width: containerWidth, height: layout.size.height)

        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: containerWidth,
            height: layout.size.height
        )
        textView.textContainer?.containerSize = NSSize(
            width: containerWidth,
            height: layout.size.height
        )

        guard let attrString = layout.attributedString, attrString.length > 0 else {
            resetNonTextState(textView)
            clearText(in: textView)
            return
        }

        textView.onCheckboxToggle = onCheckboxToggle
        textView.onLinkTap = onLinkTap
        textView.onSummaryClick = nil
        textView.summaryCharacterRange = NSRange(location: NSNotFound, length: 0)

        if let details = layout.node as? DetailsNode {
            textView.summaryCharacterRange = detailsSummaryRange(in: attrString.string)
            textView.onSummaryClick = { onToggleDetails?(details) }
        }

        // Replace text storage content with our pre-styled attributed string
        textView.textStorage?.setAttributedString(attrString)
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        let accessibility = PlatformAccessibility.appKitProjection(for: layout)
        textView.setAccessibilityElement(true)
        textView.setAccessibilityRole(accessibility.role)
        textView.setAccessibilityLabel(accessibility.label)
        textView.setProjectedAccessibilityValue(accessibility.value)
        textView.setAccessibilityHelp(accessibility.help)

        if layout.node is CodeBlockNode || layout.node is DiagramNode {
            textView.drawsBackground = true
            textView.backgroundColor = theme.resolved(for: layout.appearance).colors.codeColor.background
            textView.wantsLayer = true
            textView.layer?.cornerRadius = theme.codeBlock.macOSCornerRadius
            textView.textContainerInset = theme.codeBlock.macOSTextContainerInset
        } else {
            resetStyling(textView)
        }
    }

    private func resetNonTextState(_ textView: InteractiveTextView) {
        textView.onSummaryClick = nil
        textView.onCheckboxToggle = nil
        textView.onLinkTap = nil
        textView.summaryCharacterRange = NSRange(location: NSNotFound, length: 0)

        textView.setAccessibilityElement(false)
        textView.setAccessibilityRole(.none)
        textView.setAccessibilityLabel(nil)
        textView.setProjectedAccessibilityValue(nil)
        textView.setAccessibilityHelp(nil)

        resetStyling(textView)
    }

    private func resetStyling(_ textView: InteractiveTextView) {
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.layer?.cornerRadius = 0
        textView.textContainerInset = .zero
        textView.wantsLayer = false
    }

    private func clearText(in textView: InteractiveTextView) {
        textView.textStorage?.setAttributedString(NSAttributedString())
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
