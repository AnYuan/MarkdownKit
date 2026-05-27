//
//  AsyncTextView.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A Texture-inspired asynchronous native view.
/// This view does NOT use `UITextView` or `UILabel` internally. Instead, it maintains a lightweight `CALayer`.
/// Upon receiving a `LayoutResult`, it dispatches text drawing to a background GCD queue,
/// generating a `CGImage` of the text pixel-perfectly, and then sets the `layer.contents` on the main thread.
/// This utterly eliminates main-thread blocking when scrolling millions of words.
///
/// Interaction is handled via TextKit 1 hit-testing on the original `NSAttributedString`
/// (same approach as Texture's ASTextNode2), with a highlight overlay CALayer for pressed state.
public class AsyncTextView: UIView {

    /// The theme controlling highlight style and other visual parameters.
    public var theme: Theme = .default

    /// When `true` (the default), text is rasterized on a background executor and
    /// mounted to `layer.contents` asynchronously — identical to Texture's display pipeline.
    /// Set to `false` to render synchronously on the main thread, which is useful for
    /// snapshot testing and small-content previews.
    public var displaysAsynchronously: Bool = true

    // MARK: - Interaction Callbacks

    /// Called when the user taps a link. If nil, links open via `UIApplication.shared.open()`.
    public var onLinkTap: ((URL) -> Void)?

    /// Called when the user taps a checkbox prefix.
    public var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?

    /// Set of custom attribute keys that should trigger tap callbacks.
    public var customInteractiveAttributes: Set<NSAttributedString.Key> = []

    /// Called when a tap lands on a character with a registered custom interactive attribute.
    public var onCustomAttributeTap: ((NSAttributedString.Key, Any) -> Void)?

    // MARK: - Private State

    private var currentDrawTask: Task<Void, Never>?

    /// Retained for hit-testing after rasterization. Public read for content-change detection.
    public private(set) var currentAttributedString: NSAttributedString?
    private var currentSize: CGSize = .zero

    /// Custom CGContext drawing closure from `LayoutResult.customDraw`.
    /// When set, rasterization uses this instead of TextKit.
    private var currentCustomDraw: (@Sendable (CGContext, CGSize) -> Void)?

    /// Lazily created on first tap. Invalidated on reconfigure.
    private var hitTester: TextKitHitTester?

    /// Semi-transparent overlay for pressed-state visual feedback.
    /// Inspired by Texture's ASHighlightOverlayLayer.
    private lazy var highlightLayer: CALayer = {
        let hl = CALayer()
        hl.cornerRadius = theme.highlight.cornerRadius
        hl.isHidden = true
        return hl
    }()

    /// Cached display scale, refreshed whenever the view moves between windows
    /// (e.g. external display, iPad split-view). Replaces deprecated
    /// `UIScreen.main.scale`, which returns the wrong value in multi-screen
    /// setups since iOS 16.
    private var currentDisplayScale: CGFloat = 1

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.backgroundColor = .clear
        // Pin old content at top-left during frame resizes so it doesn't stretch/distort
        // while the new async draw is in-flight. Prevents visual flicker during streaming.
        self.layer.contentsGravity = .topLeft
        self.currentDisplayScale = resolveDisplayScale()
        self.layer.contentsScale = currentDisplayScale

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        let pressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        pressGesture.minimumPressDuration = 0.05
        pressGesture.cancelsTouchesInView = false
        addGestureRecognizer(pressGesture)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // When the view enters a new window (e.g. moved to an external
        // display) the display scale may change. Refresh to keep rasterized
        // text crisp.
        let newScale = resolveDisplayScale()
        if newScale != currentDisplayScale {
            currentDisplayScale = newScale
            layer.contentsScale = newScale
        }
    }

    private func resolveDisplayScale() -> CGFloat {
        // Prefer the window's screen so external displays return the correct
        // value. `traitCollection.displayScale` is the canonical fallback once
        // the view is attached but before the window's scene resolves.
        if let scale = window?.windowScene?.screen.scale, scale > 0 {
            return scale
        }
        let trait = traitCollection.displayScale
        return trait > 0 ? trait : 2
    }

    // MARK: - Reuse

    /// Resets internal state so the view can be reused by a recycling cell.
    /// Does **not** remove the view from its superview — the caller keeps the
    /// instance alive across cell recycles to amortize allocation cost.
    public func prepareForReuse() {
        currentDrawTask?.cancel()
        currentDrawTask = nil
        currentAttributedString = nil
        currentSize = .zero
        currentCustomDraw = nil
        hitTester = nil
        // Clear the rasterized contents so stale text doesn't briefly flash before the
        // next async draw lands.
        layer.contents = nil
        // Detach the highlight overlay if it was previously laid over a different node.
        highlightLayer.isHidden = true
        highlightLayer.opacity = 0
    }

    // MARK: - Configure

    /// Binds the `LayoutResult` constraint to the view, launching an asynchronous drawing operation.
    public func configure(with layout: LayoutResult) {
        // Cancel any pending draw operation if this view was recycled quickly
        currentDrawTask?.cancel()
        hitTester = nil // Invalidate stale hit-tester on reconfigure

        self.frame.size = layout.size
        self.currentSize = layout.size
        self.currentCustomDraw = layout.customDraw

        // Custom draw path: bypass TextKit entirely (e.g. table card rendering)
        if let customDraw = layout.customDraw {
            self.currentAttributedString = layout.attributedString
            let size = layout.size
            let scale = currentDisplayScale

            if displaysAsynchronously {
                currentDrawTask = Task {
                    let cgImage = await Self.renderImageCustom(
                        customDraw: customDraw,
                        size: size,
                        scale: scale
                    )
                    if !Task.isCancelled {
                        self.layer.contents = cgImage
                    }
                }
            } else {
                self.layer.contents = Self.renderImageSyncCustom(
                    customDraw: customDraw,
                    size: size,
                    scale: scale
                )
            }
            return
        }

        guard let string = layout.attributedString, string.length > 0 else {
            self.currentAttributedString = nil
            // Keep layer.contents — old rendered content remains visible as placeholder
            return
        }

        self.currentAttributedString = string

        let size = layout.size
        let scale = currentDisplayScale

        if displaysAsynchronously {
            nonisolated(unsafe) let drawString = NSAttributedString(attributedString: string)
            currentDrawTask = Task {
                let cgImage = await Self.renderImage(
                    drawString: drawString,
                    size: size,
                    scale: scale
                )
                if !Task.isCancelled {
                    self.layer.contents = cgImage
                }
            }
        } else {
            self.layer.contents = Self.renderImageSync(
                drawString: string,
                size: size,
                scale: scale
            )
        }
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let attrString = currentAttributedString else { return }
        let point = gesture.location(in: self)

        if hitTester == nil {
            hitTester = TextKitHitTester(attributedString: attrString, containerSize: currentSize)
        }

        guard let charIndex = hitTester?.characterIndex(at: point) else { return }

        // 1. Check for link
        if let url: URL = hitTester?.attribute(.link, at: charIndex) {
            if let handler = onLinkTap {
                handler(url)
            } else {
                UIApplication.shared.open(url)
            }
            return
        }

        // 2. Check for checkbox
        if let data: CheckboxInteractionData = hitTester?.attribute(.markdownCheckbox, at: charIndex) {
            onCheckboxToggle?(data)
            return
        }

        // 3. Check custom interactive attributes
        if let attrString = currentAttributedString, charIndex < attrString.length {
            for key in customInteractiveAttributes {
                let value = attrString.attribute(key, at: charIndex, effectiveRange: nil)
                if let value {
                    onCustomAttributeTap?(key, value)
                    return
                }
            }
        }
    }

    // MARK: - Press Highlight

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            showHighlight(at: gesture.location(in: self))
        case .ended, .cancelled, .failed:
            hideHighlight()
        default:
            break
        }
    }

    private func showHighlight(at point: CGPoint) {
        guard let attrString = currentAttributedString else { return }

        if hitTester == nil {
            hitTester = TextKitHitTester(attributedString: attrString, containerSize: currentSize)
        }

        guard let charIndex = hitTester?.characterIndex(at: point) else { return }

        // Determine the interactive range to highlight
        var highlightRange: NSRange?

        if hitTester?.effectiveRange(of: .link, at: charIndex) != nil {
            highlightRange = hitTester?.effectiveRange(of: .link, at: charIndex)
        } else if hitTester?.effectiveRange(of: .markdownCheckbox, at: charIndex) != nil {
            highlightRange = hitTester?.effectiveRange(of: .markdownCheckbox, at: charIndex)
        } else {
            for key in customInteractiveAttributes {
                if let range = hitTester?.effectiveRange(of: key, at: charIndex) {
                    highlightRange = range
                    break
                }
            }
        }

        guard let range = highlightRange,
              let rect = hitTester?.boundingRect(for: range) else { return }

        // Texture-inspired highlight
        let isDark = traitCollection.userInterfaceStyle == .dark
        let hlStyle = theme.highlight
        highlightLayer.backgroundColor = UIColor.systemBlue.withAlphaComponent(isDark ? hlStyle.darkModeAlpha : hlStyle.lightModeAlpha).cgColor

        if highlightLayer.superlayer == nil {
            layer.addSublayer(highlightLayer)
        }

        highlightLayer.frame = rect.insetBy(dx: hlStyle.insetDX, dy: hlStyle.insetDY)
        highlightLayer.opacity = 0
        highlightLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(hlStyle.fadeInDuration)
        highlightLayer.opacity = 1
        CATransaction.commit()
    }

    private func hideHighlight() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(theme.highlight.fadeOutDuration)
        CATransaction.setCompletionBlock { [weak self] in
            self?.highlightLayer.isHidden = true
        }
        highlightLayer.opacity = 0
        CATransaction.commit()
    }

    // MARK: - Rendering

    /// Renders synchronously on the calling thread. Used when `displaysAsynchronously` is `false`.
    private static func renderImageSync(
        drawString: NSAttributedString,
        size: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            drawAttributedString(drawString, in: CGRect(origin: .zero, size: size))
        }
        return image.cgImage
    }

    /// Renders the attributed string into a bitmap on a background executor.
    private static nonisolated func renderImage(
        drawString: sending NSAttributedString,
        size: CGSize,
        scale: CGFloat
    ) async -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { _ in
            drawAttributedString(drawString, in: CGRect(origin: .zero, size: size))
        }
        return image.cgImage
    }

    private static func drawAttributedString(
        _ drawString: NSAttributedString,
        in drawRect: CGRect
    ) {
        let textStorage = NSTextStorage(attributedString: drawString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: drawRect.size)

        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: drawRect.origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawRect.origin)
    }

    // MARK: - Custom Draw Rendering

    /// Renders synchronously using a custom draw closure.
    private static func renderImageSyncCustom(
        customDraw: @Sendable (CGContext, CGSize) -> Void,
        size: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            customDraw(rendererContext.cgContext, size)
        }
        return image.cgImage
    }

    /// Renders using a custom draw closure on a background executor.
    private static nonisolated func renderImageCustom(
        customDraw: @Sendable (CGContext, CGSize) -> Void,
        size: CGSize,
        scale: CGFloat
    ) async -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            customDraw(rendererContext.cgContext, size)
        }
        return image.cgImage
    }
}

/// A read-only native text surface that keeps MarkdownKit styling while enabling
/// system text selection, copy, and edit-menu behavior.
public final class SelectableTextView: UITextView {

    public var onLinkTap: ((URL) -> Void)?
    public var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    public var customInteractiveAttributes: Set<NSAttributedString.Key> = []
    public var onCustomAttributeTap: ((NSAttributedString.Key, Any) -> Void)?

    public private(set) var currentAttributedString: NSAttributedString?

    private lazy var interactionTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleInteractionTap(_:)))
        gesture.cancelsTouchesInView = true
        gesture.delegate = self
        return gesture
    }()

    public convenience init(frame: CGRect) {
        self.init(frame: frame, textContainer: nil)
    }

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        contentInset = .zero
        delegate = self
        addGestureRecognizer(interactionTapGesture)
    }

    public func configure(with layout: LayoutResult) {
        frame.size = layout.size
        textContainer.size = layout.size

        guard let attributedString = layout.attributedString, attributedString.length > 0 else {
            currentAttributedString = nil
            attributedText = nil
            return
        }

        currentAttributedString = attributedString
        attributedText = attributedString
        layoutManager.ensureLayout(for: textContainer)
    }

    /// Resets selectable state so the view can be reused by a recycling cell.
    public func prepareForReuse() {
        currentAttributedString = nil
        attributedText = nil
    }

    @objc private func handleInteractionTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let hit = interactionHit(at: gesture.location(in: self)) else { return }

        switch hit {
        case let .checkbox(data):
            onCheckboxToggle?(data)
        case let .customAttribute(key, value):
            onCustomAttributeTap?(key, value)
        }
    }

    private func interactionHit(at point: CGPoint) -> InteractionHit? {
        guard let attributedString = currentAttributedString, attributedString.length > 0 else { return nil }
        guard let characterIndex = characterIndex(at: point) else { return nil }

        if let data = attributedString.attribute(.markdownCheckbox, at: characterIndex, effectiveRange: nil) as? CheckboxInteractionData {
            return .checkbox(data)
        }

        for key in customInteractiveAttributes {
            if let value = attributedString.attribute(key, at: characterIndex, effectiveRange: nil) {
                return .customAttribute(key, value)
            }
        }

        return nil
    }

    private func characterIndex(at point: CGPoint) -> Int? {
        guard let position = closestPosition(to: point),
              let textRange = tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: UITextDirection.storage(.forward)) else {
            return nil
        }

        let index = offset(from: beginningOfDocument, to: textRange.start)
        guard let attributedString = currentAttributedString, index >= 0, index < attributedString.length else { return nil }
        return index
    }

    private enum InteractionHit {
        case checkbox(CheckboxInteractionData)
        case customAttribute(NSAttributedString.Key, Any)
    }
}

extension SelectableTextView: UITextViewDelegate {
    public func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if let onLinkTap {
            onLinkTap(url)
            return false
        }

        return true
    }
}

extension SelectableTextView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        interactionHit(at: touch.location(in: self)) != nil
    }
}
#endif
