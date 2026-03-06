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

    /// Lazily created on first tap. Invalidated on reconfigure.
    private var hitTester: TextKitHitTester?

    /// Semi-transparent overlay for pressed-state visual feedback.
    /// Inspired by Texture's ASHighlightOverlayLayer.
    private lazy var highlightLayer: CALayer = {
        let hl = CALayer()
        hl.cornerRadius = 3
        hl.isHidden = true
        return hl
    }()

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
        self.layer.contentsScale = UIScreen.main.scale

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        let pressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        pressGesture.minimumPressDuration = 0.05
        pressGesture.cancelsTouchesInView = false
        addGestureRecognizer(pressGesture)
    }

    // MARK: - Configure

    /// Binds the `LayoutResult` constraint to the view, launching an asynchronous drawing operation.
    public func configure(with layout: LayoutResult) {
        // Cancel any pending draw operation if this view was recycled quickly
        currentDrawTask?.cancel()
        hitTester = nil // Invalidate stale hit-tester on reconfigure

        self.frame.size = layout.size
        self.currentSize = layout.size

        guard let string = layout.attributedString, string.length > 0 else {
            self.currentAttributedString = nil
            // Keep layer.contents — old rendered content remains visible as placeholder
            return
        }

        self.currentAttributedString = string

        let size = layout.size
        let scale = UIScreen.main.scale

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

        // Texture-inspired highlight: light=0.11 / dark=0.22 opacity
        let isDark = traitCollection.userInterfaceStyle == .dark
        highlightLayer.backgroundColor = UIColor.systemBlue.withAlphaComponent(isDark ? 0.22 : 0.11).cgColor

        if highlightLayer.superlayer == nil {
            layer.addSublayer(highlightLayer)
        }

        // Animate in (Texture: fadeIn 0.1s)
        highlightLayer.frame = rect.insetBy(dx: -2, dy: -1)
        highlightLayer.opacity = 0
        highlightLayer.isHidden = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        highlightLayer.opacity = 1
        CATransaction.commit()
    }

    private func hideHighlight() {
        // Animate out (Texture: fadeOut 0.15s)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
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
            let drawRect = CGRect(origin: .zero, size: size)
            drawString.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin],
                context: nil
            )
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
            let drawRect = CGRect(origin: .zero, size: size)
            drawString.draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin],
                context: nil
            )
        }
        return image.cgImage
    }
}
#endif
