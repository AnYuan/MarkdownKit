import Foundation
import MathJaxSwift
import SwiftDraw
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Default math rendering adapter that uses MathJaxSwift (LaTeX → SVG) and
/// SwiftDraw (SVG → UIImage) for precise, synchronous rasterization.
///
/// Previous implementation used WKWebView snapshots which caused imprecise
/// heights due to layout timing. SwiftDraw renders SVG directly via
/// CoreGraphics, producing exact dimensions without async WebView overhead.
public struct DefaultMathRenderingAdapter: MathRenderingAdapter {

    public init() {}

    // MARK: - MathRenderingAdapter

    public func render(from node: MathNode, theme: Theme, contextFont: Font?) async -> NSAttributedString {
        let hex = Self.hexColor(theme.colors.textColor.foreground)
        let display = !node.isInline
        let effectiveFont = contextFont ?? theme.typography.paragraph.font

        // Check image cache first
        let imgKey = Self.imageCacheKey(latex: node.equation, display: display, textColor: hex, fontSize: effectiveFont.pointSize)
        if let cached = Self.imageCache.object(forKey: imgKey as NSString) {
            return Self.attachmentString(image: cached, node: node, font: effectiveFont)
        }

        // Get SVG string (cached or freshly converted)
        let svgKey = Self.svgCacheKey(latex: node.equation, display: display, fontSize: effectiveFont.pointSize)
        let svgString: String
        if let cached = Self.svgCache.object(forKey: svgKey as NSString) {
            svgString = cached as String
        } else {
            do {
                let generated = try await engine.tex2svg(node.equation, display: display)
                Self.svgCache.setObject(generated as NSString, forKey: svgKey as NSString)
                svgString = generated
            } catch {
                if await warningSuppressor.shouldLog(String(describing: error)) {
                    Self.logger.error("MathJaxSwift conversion failed: \(String(describing: error))")
                }
                return Self.fallbackString(for: node, theme: theme)
            }
        }

        // Pre-process and rasterize via SwiftDraw
        guard let image = Self.rasterize(svgString: svgString, font: effectiveFont, textColor: hex) else {
            return Self.fallbackString(for: node, theme: theme)
        }

        Self.imageCache.setObject(image, forKey: imgKey as NSString)
        return Self.attachmentString(image: image, node: node, font: effectiveFont)
    }

    public func renderSync(from node: MathNode, theme: Theme, contextFont: Font?) -> NSAttributedString {
        let hex = Self.hexColor(theme.colors.textColor.foreground)
        let display = !node.isInline
        let effectiveFont = contextFont ?? theme.typography.paragraph.font

        // Check image cache
        let imgKey = Self.imageCacheKey(latex: node.equation, display: display, textColor: hex, fontSize: effectiveFont.pointSize)
        if let cached = Self.imageCache.object(forKey: imgKey as NSString) {
            return Self.attachmentString(image: cached, node: node, font: effectiveFont)
        }

        // If SVG is cached from a prior async render, we can rasterize synchronously
        let svgKey = Self.svgCacheKey(latex: node.equation, display: display, fontSize: effectiveFont.pointSize)
        guard let cachedSVG = Self.svgCache.object(forKey: svgKey as NSString) as String? else {
            return Self.fallbackString(for: node, theme: theme)
        }

        guard let image = Self.rasterize(svgString: cachedSVG, font: effectiveFont, textColor: hex) else {
            return Self.fallbackString(for: node, theme: theme)
        }

        Self.imageCache.setObject(image, forKey: imgKey as NSString)
        return Self.attachmentString(image: image, node: node, font: effectiveFont)
    }

    // MARK: - Engine (MathJaxSwift)

    /// Actor-isolated MathJaxSwift wrapper for thread-safe LaTeX → SVG conversion.
    private actor Engine {
        private var mathJax: MathJax?

        private func makeTeXInputOptions() -> TeXInputProcessorOptions {
            let opts = TeXInputProcessorOptions()
            opts.loadPackages = [
                TeXInputProcessorOptions.Packages.base,
                TeXInputProcessorOptions.Packages.ams,
                TeXInputProcessorOptions.Packages.newcommand,
                TeXInputProcessorOptions.Packages.boldsymbol,
            ]
            return opts
        }

        func tex2svg(_ latex: String, display: Bool) throws -> String {
            let engine: MathJax
            if let existing = mathJax {
                engine = existing
            } else {
                let created = try MathJax(preferredOutputFormat: .svg)
                mathJax = created
                engine = created
            }
            let conversionOptions = ConversionOptions(display: display)
            return try engine.tex2svg(
                latex,
                css: false,
                assistiveMml: false,
                container: false,
                styles: false,
                conversionOptions: conversionOptions,
                inputOptions: makeTeXInputOptions()
            )
        }
    }

    private let engine = Engine()
    private let warningSuppressor = MathWarningSuppressor()
    private static let logger = Logger(subsystem: "com.markdownkit", category: "MathRenderer")

    // MARK: - Caching

    /// SVG string cache: keyed by (latex, display). Color-independent since MathJax SVGs use `currentColor`.
    /// `countLimit` is a soft cap (NSCache may evict earlier under memory pressure).
    private nonisolated(unsafe) static let svgCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()

    /// Rendered image cache: keyed by (latex, display, textColor). Color-dependent.
    private nonisolated(unsafe) static let imageCache: NSCache<NSString, NativeImage> = {
        let cache = NSCache<NSString, NativeImage>()
        cache.countLimit = 512
        return cache
    }()

    /// Drops all cached SVGs and rasterized images. Hosts can call this from
    /// memory-warning handlers or when switching color schemes wholesale.
    public static func clearCaches() {
        svgCache.removeAllObjects()
        imageCache.removeAllObjects()
    }

    private static func svgCacheKey(latex: String, display: Bool, fontSize: CGFloat) -> String {
        "\(latex)::display=\(display)::fontSize=\(fontSize)"
    }

    private static func imageCacheKey(latex: String, display: Bool, textColor: String?, fontSize: CGFloat) -> String {
        var key = "\(latex)::display=\(display)::fontSize=\(fontSize)"
        if let textColor { key += "::color=\(textColor)" }
        return key
    }

    // MARK: - Rasterization

    /// Pre-processes and rasterizes an SVG string via SwiftDraw.
    /// Returns nil if SVG parsing or rasterization fails.
    private static func rasterize(svgString: String, font: Font, textColor: String?) -> NativeImage? {
        let fontXHeight = font.xHeight
        let processed = MathSVGPreprocessor.preprocess(
            svg: svgString,
            fontXHeight: fontXHeight,
            textColor: textColor
        )

        guard processed.size.width > 0, processed.size.height > 0,
              var svg = SVG(xml: processed.svg) else {
            return nil
        }

        // Scale from viewBox dimensions to exact point dimensions
        svg.size(processed.size)

        let image = svg.rasterize()
        return Self.normalizedImage(image, targetSize: processed.size)
    }

#if canImport(UIKit)
    /// SwiftDraw's UIKit rasterization rounds the point-size bounds up to the
    /// next whole point before rendering, so the resulting `UIImage.size` can
    /// overshoot the preprocessed SVG's logical size. `UIImage.size` is
    /// get-only and derived from `scale` (`cgImage` pixel size / `scale`), so
    /// rewrap the same `cgImage` with a `scale` chosen to make the reported
    /// width match the target exactly (height matches to within sub-point
    /// rounding) without resampling any pixels or mutating read-only state.
    private static func normalizedImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        guard let cgImage = image.cgImage, targetSize.width > 0 else { return image }
        let scale = CGFloat(cgImage.width) / targetSize.width
        guard scale.isFinite, scale > 0 else { return image }
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
    }
#elseif canImport(AppKit)
    /// SwiftDraw's AppKit rasterization reports the image size in device
    /// pixels rather than logical points, so reset it to the preprocessed
    /// SVG's exact logical point size for correct attachment bounds.
    private static func normalizedImage(_ image: NSImage, targetSize: CGSize) -> NSImage {
        image.size = targetSize
        return image
    }
#endif

    // MARK: - Attachment

    private static func attachmentString(image: NativeImage, node: MathNode, font: Font) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = attachmentBounds(for: image.size, isInline: node.isInline, font: font)

        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        if !node.isInline {
            result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        }
        return result
    }

    // MARK: - Helpers

    /// Converts a native color to a CSS hex string (e.g. "#FFFFFF").
    static func hexColor(_ color: Color) -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if canImport(UIKit)
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #elseif canImport(AppKit)
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

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
