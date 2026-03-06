import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Default math rendering adapter that uses `MathRenderer` (WebKit + MathJaxSwift)
/// for async rendering and cached images for sync rendering.
public struct DefaultMathRenderingAdapter: MathRenderingAdapter {

    public init() {}

    public func render(from node: MathNode, theme: Theme) async -> NSAttributedString {
        #if canImport(WebKit)
        if let image = await renderMath(latex: node.equation, display: !node.isInline) {
            return Self.attachmentString(image: image, node: node, theme: theme)
        }
        #endif
        return Self.fallbackString(for: node, theme: theme)
    }

    public func renderSync(from node: MathNode, theme: Theme) -> NSAttributedString {
        #if canImport(WebKit)
        if let image = MathRenderer.cachedImage(for: node.equation) {
            return Self.attachmentString(image: image, node: node, theme: theme)
        }
        #endif
        return Self.fallbackString(for: node, theme: theme)
    }

    private static func attachmentString(image: NativeImage, node: MathNode, theme: Theme) -> NSAttributedString {
        let font = theme.typography.paragraph.font
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = attachmentBounds(for: image.size, isInline: node.isInline, font: font)

        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        // Block math gets a trailing newline so it occupies its own line
        // when merged with other blocks into a single attributed string.
        if !node.isInline {
            result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        }
        return result
    }

    // MARK: - Helpers

    #if canImport(WebKit)
    private func renderMath(latex: String, display: Bool) async -> NativeImage? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                MathRenderer.shared.render(latex: latex, display: display) { image in
                    continuation.resume(returning: image)
                }
            }
        }
    }
    #endif

    static func attachmentBounds(for imageSize: CGSize, isInline: Bool, font: Font) -> CGRect {
        guard isInline else {
            return CGRect(origin: .zero, size: imageSize)
        }
        let textMidline = (font.ascender + font.descender) / 2.0
        let imageMidline = imageSize.height / 2.0
        let offsetY = textMidline - imageMidline
        return CGRect(x: 0, y: offsetY, width: imageSize.width, height: imageSize.height)
    }

    static func fallbackString(for node: MathNode, theme: Theme) -> NSAttributedString {
        let token = theme.typography.codeBlock
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = token.lineHeightMultiple
        style.paragraphSpacing = token.paragraphSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: token.font,
            .paragraphStyle: style,
            .foregroundColor: theme.colors.textColor.foreground,
        ]
        return NSAttributedString(string: node.equation, attributes: attrs)
    }
}
