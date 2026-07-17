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
/// This keeps text rasterization out of the main-thread scroll path.
///
/// Interaction is handled via TextKit 1 hit-testing on the original `NSAttributedString`
/// (same approach as Texture's ASTextNode2), with a highlight overlay CALayer for pressed state.
class AsyncTextView: UIView {

    /// The theme controlling highlight style and other visual parameters.
    var theme: Theme = .default

    /// When `true` (the default), text is rasterized on a background executor and
    /// mounted to `layer.contents` asynchronously — identical to Texture's display pipeline.
    /// Set to `false` to render synchronously on the main thread, which is useful for
    /// snapshot testing and small-content previews.
    var displaysAsynchronously: Bool = true

    // MARK: - Interaction Callbacks

    /// Called when the user taps a link. If nil, links open via `UIApplication.shared.open()`.
    var onLinkTap: ((URL) -> Void)?

    /// Called when the user taps a checkbox prefix.
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?

    /// Set of custom attribute keys that should trigger tap callbacks.
    var customInteractiveAttributes: Set<NSAttributedString.Key> = []

    /// Called when a tap lands on a character with a registered custom interactive attribute.
    var onCustomAttributeTap: ((NSAttributedString.Key, Any) -> Void)?

    // MARK: - Private State

    private var currentDrawTask: Task<Void, Never>?

    /// Retained for hit-testing after rasterization and internal content-change checks.
    private(set) var currentAttributedString: NSAttributedString?
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

    /// Shared cache of rasterized text bitmaps. Key is render-variant based
    /// (`renderFingerprint + size + scale`), NOT identity-based — using
    /// `NSAttributedString.hash` would miss because `NSObject` hashes by
    /// pointer, and two equal attributed strings have different pointers.
    /// Cross-cell scroll-back and prefetch both benefit from this cache.
    /// `countLimit` is a soft cap.
    nonisolated(unsafe) private static let imageCache: NSCache<NSString, CGImageWrapper> = {
        let c = NSCache<NSString, CGImageWrapper>()
        c.countLimit = 128
        return c
    }()

    /// `CGImage` is a CoreFoundation type that bridges to AnyObject but cannot
    /// be stored directly in `NSCache<NSString, CGImage>` (the generic bound
    /// requires `AnyObject`-conforming Swift class). A thin wrapper avoids
    /// `Unmanaged` gymnastics.
    private final class CGImageWrapper {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Drops all cached rasterized bitmaps. The cache also auto-evicts under pressure.
    static func clearImageCache() {
        imageCache.removeAllObjects()
    }

    static func imageCacheKey(
        renderFingerprint: Int,
        appearance: MarkdownAppearance,
        size: CGSize,
        scale: CGFloat
    ) -> String {
        "\(renderFingerprint)|\(appearance)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))@\(scale)"
    }

    /// Pre-rasterizes a layout's bitmap on a background task so it's ready in
    /// the cache by the time the cell scrolls into view. No-op if the bitmap
    /// is already cached. Used by
    /// `UICollectionViewDataSourcePrefetching.prefetchItemsAt`.
    ///
    /// Caller is responsible for retaining the returned `Task` so it can be
    /// cancelled in `cancelPrefetchingForItemsAt` when scrolling reverses.
    static func preheat(_ layout: LayoutResult, scale: CGFloat = 2) -> Task<Void, Never> {
        let size = layout.size
        let appearance = layout.appearance
        let cacheKey = imageCacheKey(
            renderFingerprint: layout.renderFingerprint,
            appearance: appearance,
            size: size,
            scale: scale
        )

        // Already cached? Return an instantly-finished no-op task.
        if imageCache.object(forKey: cacheKey as NSString) != nil {
            return Task {}
        }

        if let customDraw = layout.customDraw {
            return Task.detached(priority: .utility) {
                let cgImage = await renderImageCustom(
                    customDraw: customDraw,
                    size: size,
                    scale: scale,
                    appearance: appearance
                )
                if Task.isCancelled { return }
                if let cgImage {
                    imageCache.setObject(CGImageWrapper(cgImage), forKey: cacheKey as NSString)
                }
            }
        }

        guard let attributedString = layout.attributedString, attributedString.length > 0 else {
            return Task {}
        }

        // Bridge `NSAttributedString` (not formally Sendable) into the detached
        // task by copying. The cell-driven render path uses the same pattern.
        nonisolated(unsafe) let drawString = NSAttributedString(attributedString: attributedString)
        return Task.detached(priority: .utility) {
            let cgImage = await renderImage(
                drawString: drawString,
                size: size,
                scale: scale,
                appearance: appearance
            )
            if Task.isCancelled { return }
            if let cgImage {
                imageCache.setObject(CGImageWrapper(cgImage), forKey: cacheKey as NSString)
            }
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
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

    override func didMoveToWindow() {
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
    func prepareForReuse() {
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
    func configure(with layout: LayoutResult) {
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
            let cacheKey = Self.imageCacheKey(
                renderFingerprint: layout.renderFingerprint,
                appearance: layout.appearance,
                size: size,
                scale: scale
            )

            // Cache hit: mount synchronously, skip the rasterization Task.
            if let cached = Self.imageCache.object(forKey: cacheKey as NSString) {
                layer.contents = cached.image
                return
            }

            if displaysAsynchronously {
                currentDrawTask = Task {
                    let cgImage = await Self.renderImageCustom(
                        customDraw: customDraw,
                        size: size,
                        scale: scale,
                        appearance: layout.appearance
                    )
                    if Task.isCancelled { return }
                    if let cgImage {
                        Self.imageCache.setObject(CGImageWrapper(cgImage), forKey: cacheKey as NSString)
                    }
                    self.layer.contents = cgImage
                }
            } else {
                let cgImage = Self.renderImageSyncCustom(
                    customDraw: customDraw,
                    size: size,
                    scale: scale,
                    appearance: layout.appearance
                )
                if let cgImage {
                    Self.imageCache.setObject(CGImageWrapper(cgImage), forKey: cacheKey as NSString)
                }
                self.layer.contents = cgImage
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
        let cacheKey = Self.imageCacheKey(
            renderFingerprint: layout.renderFingerprint,
            appearance: layout.appearance,
            size: size,
            scale: scale
        )

        // Cache hit: scroll-back or prefetch warmup landed here first.
        if let cached = Self.imageCache.object(forKey: cacheKey as NSString) {
            layer.contents = cached.image
            return
        }

        if displaysAsynchronously {
            nonisolated(unsafe) let drawString = NSAttributedString(attributedString: string)
            currentDrawTask = Task {
                let cgImage = await Self.renderImage(
                    drawString: drawString,
                    size: size,
                    scale: scale,
                    appearance: layout.appearance
                )
                if Task.isCancelled { return }
                if let cgImage {
                    Self.imageCache.setObject(CGImageWrapper(cgImage), forKey: cacheKey as NSString)
                }
                self.layer.contents = cgImage
            }
        } else {
            let cgImage = Self.renderImageSync(
                drawString: string,
                size: size,
                scale: scale,
                appearance: layout.appearance
            )
            if let cgImage {
                Self.imageCache.setObject(CGImageWrapper(cgImage), forKey: cacheKey as NSString)
            }
            self.layer.contents = cgImage
        }
    }

    // MARK: - Tap Handling

    private func interactionHitTester() -> TextKitHitTester? {
        guard let attrString = currentAttributedString else { return nil }

        if hitTester == nil {
            hitTester = TextKitHitTester(attributedString: attrString, containerSize: currentSize)
        }

        return hitTester
    }

    @discardableResult
    func handleInteraction(at point: CGPoint) -> Bool {
        guard let attrString = currentAttributedString,
              let hitTester = interactionHitTester(),
              let charIndex = hitTester.characterIndex(at: point) else {
            return false
        }

        // 1. Check for link
        if let url: URL = hitTester.attribute(.link, at: charIndex) {
            if let handler = onLinkTap {
                handler(url)
            } else {
                UIApplication.shared.open(url)
            }
            return true
        }

        // 2. Check for checkbox
        if let data: CheckboxInteractionData = hitTester.attribute(.markdownCheckbox, at: charIndex) {
            onCheckboxToggle?(data)
            return true
        }

        // 3. Check custom interactive attributes
        if charIndex < attrString.length {
            for key in customInteractiveAttributes {
                let value = attrString.attribute(key, at: charIndex, effectiveRange: nil)
                if let value {
                    onCustomAttributeTap?(key, value)
                    return true
                }
            }
        }

        return false
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handleInteraction(at: gesture.location(in: self))
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
        guard let hitTester = interactionHitTester(),
              let charIndex = hitTester.characterIndex(at: point) else { return }

        // Determine the interactive range to highlight
        var highlightRange: NSRange?

        if hitTester.effectiveRange(of: .link, at: charIndex) != nil {
            highlightRange = hitTester.effectiveRange(of: .link, at: charIndex)
        } else if hitTester.effectiveRange(of: .markdownCheckbox, at: charIndex) != nil {
            highlightRange = hitTester.effectiveRange(of: .markdownCheckbox, at: charIndex)
        } else {
            for key in customInteractiveAttributes {
                if let range = hitTester.effectiveRange(of: key, at: charIndex) {
                    highlightRange = range
                    break
                }
            }
        }

        guard let range = highlightRange,
              range.length > 0 else { return }
        let rect = hitTester.boundingRect(for: range)

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
        scale: CGFloat,
        appearance: MarkdownAppearance
    ) -> CGImage? {
        let traits = renderingTraits(appearance: appearance, scale: scale)
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var renderedImage: UIImage?
        traits.performAsCurrent {
            renderedImage = renderer.image { _ in
                drawAttributedString(drawString, in: CGRect(origin: .zero, size: size))
            }
        }
        return renderedImage?.cgImage
    }

    /// Renders the attributed string into a bitmap on a background executor.
    private static nonisolated func renderImage(
        drawString: sending NSAttributedString,
        size: CGSize,
        scale: CGFloat,
        appearance: MarkdownAppearance
    ) async -> CGImage? {
        let traits = renderingTraits(appearance: appearance, scale: scale)
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var renderedImage: UIImage?
        traits.performAsCurrent {
            renderedImage = renderer.image { _ in
                drawAttributedString(drawString, in: CGRect(origin: .zero, size: size))
            }
        }
        return renderedImage?.cgImage
    }

    private static nonisolated func renderingTraits(
        appearance: MarkdownAppearance,
        scale: CGFloat
    ) -> UITraitCollection {
        let interfaceStyle: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        return UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: interfaceStyle),
            UITraitCollection(displayScale: scale)
        ])
    }

    // Explicitly `nonisolated`: as a `private static` member of a `UIView`
    // subclass this would otherwise infer `@MainActor` isolation, forcing an
    // implicit main-actor hop from the synchronous, non-async
    // `UIGraphicsImageRenderer.image(_:)` closure in `renderImage` below —
    // which is not possible without `await` and triggers a compile error.
    // The function only touches its parameters and TextKit locals, never
    // main-actor state, so it is safe to run on whatever background executor
    // the caller is isolated to.
    private static nonisolated func drawAttributedString(
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
        // Cancellation checkpoint: glyphRange computation is the heaviest
        // step. Skip the actual paint if the cell was reused / view moved on.
        // `Task.isCancelled` is `false` outside a Task, so the sync path is
        // unaffected.
        if Task.isCancelled { return }
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: drawRect.origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawRect.origin)
    }

    // MARK: - Custom Draw Rendering

    /// Renders synchronously using a custom draw closure.
    private static func renderImageSyncCustom(
        customDraw: @Sendable (CGContext, CGSize) -> Void,
        size: CGSize,
        scale: CGFloat,
        appearance: MarkdownAppearance
    ) -> CGImage? {
        let traits = renderingTraits(appearance: appearance, scale: scale)
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var renderedImage: UIImage?
        traits.performAsCurrent {
            renderedImage = renderer.image { rendererContext in
                customDraw(rendererContext.cgContext, size)
            }
        }
        return renderedImage?.cgImage
    }

    /// Renders using a custom draw closure on a background executor.
    private static nonisolated func renderImageCustom(
        customDraw: @Sendable (CGContext, CGSize) -> Void,
        size: CGSize,
        scale: CGFloat,
        appearance: MarkdownAppearance
    ) async -> CGImage? {
        let traits = renderingTraits(appearance: appearance, scale: scale)
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var renderedImage: UIImage?
        traits.performAsCurrent {
            renderedImage = renderer.image { rendererContext in
                customDraw(rendererContext.cgContext, size)
            }
        }
        return renderedImage?.cgImage
    }
}

/// A read-only native text surface that keeps MarkdownKit styling while enabling
/// system text selection, copy, and edit-menu behavior.
final class SelectableTextView: UITextView {

    var onLinkTap: ((URL) -> Void)?
    var onCheckboxToggle: ((CheckboxInteractionData) -> Void)?
    var customInteractiveAttributes: Set<NSAttributedString.Key> = []
    var onCustomAttributeTap: ((NSAttributedString.Key, Any) -> Void)?

    private(set) var currentAttributedString: NSAttributedString?

    private lazy var interactionTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleInteractionTap(_:)))
        gesture.cancelsTouchesInView = true
        gesture.delegate = self
        return gesture
    }()

    convenience init(frame: CGRect) {
        self.init(frame: frame, textContainer: nil)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
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

    func configure(with layout: LayoutResult) {
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
    func prepareForReuse() {
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
    func textView(
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
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        interactionHit(at: touch.location(in: self)) != nil
    }
}
#endif
