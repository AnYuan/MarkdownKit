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
public class AsyncTextView: UIView {

    /// When `true` (the default), text is rasterized on a background executor and
    /// mounted to `layer.contents` asynchronously — identical to Texture's display pipeline.
    /// Set to `false` to render synchronously on the main thread, which is useful for
    /// snapshot testing and small-content previews.
    public var displaysAsynchronously: Bool = true

    private var currentDrawTask: Task<Void, Never>?

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
    }

    /// Binds the `LayoutResult` constraint to the view, launching an asynchronous drawing operation.
    public func configure(with layout: LayoutResult) {
        // Cancel any pending draw operation if this view was recycled quickly
        currentDrawTask?.cancel()

        self.frame.size = layout.size

        guard let string = layout.attributedString, string.length > 0 else {
            self.layer.contents = nil
            return
        }

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
