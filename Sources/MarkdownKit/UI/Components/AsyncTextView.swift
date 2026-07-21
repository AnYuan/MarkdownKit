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
    private var currentRasterLease: RasterImageLease?
    private var currentContentLayout: RasterContentLayout?
    private var currentRasterKey: RasterRenderKey?
    private var mountedRasterKey: RasterRenderKey?
    private var configurationGeneration: UInt = 0

    /// Retained for hit-testing after rasterization and internal content-change checks.
    private(set) var currentAttributedString: NSAttributedString?
    private var currentSize: CGSize = .zero

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

    var rasterPipeline: RasterImagePipeline = .shared {
        didSet {
            guard oldValue !== rasterPipeline else { return }
            rerasterizeCurrentContent(force: true)
        }
    }

    var displayScaleOverride: CGFloat? {
        didSet {
            refreshDisplayScale()
        }
    }

    var currentRasterKeyForTesting: RasterRenderKey? {
        currentRasterKey
    }

    func drainRasterMountForTesting() async {
        await currentDrawTask?.value
    }

    static func clearImageCache() {
        RasterImagePipeline.shared.clearCache()
    }

    static func imageCacheKey(
        renderFingerprint: Int,
        appearance: MarkdownAppearance,
        size: CGSize,
        scale: CGFloat
    ) -> RasterRenderKey {
        RasterRenderKey(
            renderFingerprint: renderFingerprint,
            appearance: appearance,
            contentKind: .attributedText,
            logicalSize: size,
            displayScale: scale
        )
    }

    static func rasterKey(
        for contentLayout: RasterContentLayout,
        displayScale: CGFloat
    ) -> RasterRenderKey? {
        contentLayout.rasterKey(displayScale: displayScale)
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

    isolated deinit {
        cancelRendering()
    }

    private func setup() {
        self.backgroundColor = .clear
        // Pin old content at top-left during frame resizes so it doesn't stretch/distort
        // while the new async draw is in-flight. Prevents visual flicker during streaming.
        self.layer.contentsGravity = .topLeft
        self.currentDisplayScale = resolveDisplayScale()
        self.layer.contentsScale = currentDisplayScale

        registerForTraitChanges([UITraitDisplayScale.self]) {
            (view: AsyncTextView, _) in
            view.refreshDisplayScale()
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        let pressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        pressGesture.minimumPressDuration = 0.05
        pressGesture.cancelsTouchesInView = false
        addGestureRecognizer(pressGesture)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshDisplayScale()
    }

    private func resolveDisplayScale() -> CGFloat {
        if let displayScaleOverride,
           displayScaleOverride.isFinite,
           displayScaleOverride > 0 {
            return displayScaleOverride
        }
        // Prefer the window's screen so external displays return the correct
        // value. `traitCollection.displayScale` is the canonical fallback once
        // the view is attached but before the window's scene resolves.
        if let scale = window?.windowScene?.screen.scale, scale > 0 {
            return scale
        }
        let trait = traitCollection.displayScale
        return trait > 0 ? trait : 2
    }

    private func refreshDisplayScale() {
        let newScale = resolveDisplayScale()
        guard newScale != currentDisplayScale else { return }
        currentDisplayScale = newScale
        layer.contentsScale = newScale
        rerasterizeCurrentContent()
    }

    private func rerasterizeCurrentContent(force: Bool = false) {
        guard let currentContentLayout else { return }
        beginRasterization(for: currentContentLayout, force: force)
    }

    // MARK: - Reuse

    /// Resets internal state so the view can be reused by a recycling cell.
    /// Does **not** remove the view from its superview — the caller keeps the
    /// instance alive across cell recycles to amortize allocation cost.
    func prepareForReuse() {
        cancelRendering()
        currentAttributedString = nil
        currentSize = .zero
        currentContentLayout = nil
        currentRasterKey = nil
        mountedRasterKey = nil
        hitTester = nil
        // Clear the rasterized contents so stale text doesn't briefly flash before the
        // next async draw lands.
        layer.contents = nil
        // Detach the highlight overlay if it was previously laid over a different node.
        highlightLayer.isHidden = true
        highlightLayer.opacity = 0
    }

    func cancelRendering() {
        configurationGeneration &+= 1
        currentDrawTask?.cancel()
        currentDrawTask = nil
        currentRasterLease?.release()
        currentRasterLease = nil
    }

    // MARK: - Configure

    /// Binds the `LayoutResult` constraint to the view, launching an asynchronous drawing operation.
    func configure(with layout: LayoutResult) {
        configure(with: RasterContentLayout.resolve(layout: layout, theme: theme))
    }

    func configure(with contentLayout: RasterContentLayout) {
        hitTester = nil
        frame.size = contentLayout.size
        currentSize = contentLayout.size
        currentAttributedString = contentLayout.attributedString
        currentContentLayout = contentLayout
        beginRasterization(for: contentLayout)
    }

    private func beginRasterization(
        for contentLayout: RasterContentLayout,
        force: Bool = false
    ) {
        let scale = currentDisplayScale
        layer.contentsScale = scale

        guard let request = contentLayout.rasterRequest(
            displayScale: scale,
            priority: .userInitiated
        ) else {
            cancelRendering()
            currentRasterKey = nil
            return
        }
        let key = request.key

        let ownsReusableRaster = currentRasterLease != nil
            || currentDrawTask != nil
            || mountedRasterKey == key
        let canReuseCurrentRaster = displaysAsynchronously
            ? ownsReusableRaster
            : currentRasterLease == nil && currentDrawTask == nil && mountedRasterKey == key
        if !force, currentRasterKey == key, canReuseCurrentRaster {
            return
        }

        cancelRendering()
        let generation = configurationGeneration
        currentRasterKey = key

        guard displaysAsynchronously else {
            if let image = rasterPipeline.cachedImageIfAvailable(for: key) {
                layer.contents = image
                mountedRasterKey = key
                return
            }

            let image = request.produceSynchronously()
            if let image {
                rasterPipeline.storeDirectlyRenderedImage(image, for: key)
            }
            layer.contents = image
            mountedRasterKey = image.map { _ in key }
            return
        }

        switch rasterPipeline.acquire(request) {
        case let .cacheHit(image):
            layer.contents = image
            mountedRasterKey = key

        case let .pending(lease):
            currentRasterLease = lease
            currentDrawTask = Task { [weak self] in
                let image = await lease.value()
                guard !Task.isCancelled,
                      let self,
                      self.configurationGeneration == generation,
                      self.currentRasterLease === lease,
                      self.currentRasterKey == key else {
                    lease.release()
                    return
                }

                lease.release()
                self.currentRasterLease = nil
                self.currentDrawTask = nil
                self.layer.contents = image
                self.mountedRasterKey = image.map { _ in key }
            }
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
        guard interaction == .invokeDefaultAction else { return true }

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
