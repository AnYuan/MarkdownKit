import Foundation
import CoreGraphics

/// Pre-processes MathJax SVG strings for rendering with SwiftDraw.
///
/// MathJax SVGs use `ex` units and `currentColor` which SwiftDraw doesn't handle.
/// This preprocessor:
/// 1. Converts `ex` → unitless point values using the font's xHeight
/// 2. Replaces `currentColor` with a concrete hex color
/// 3. Strips the `style` attribute (vertical-align is for HTML embedding)
/// 4. Sets width/height to viewBox dimensions for 1:1 coordinate mapping
enum MathSVGPreprocessor {

    struct Result {
        /// The pre-processed SVG string ready for SwiftDraw.
        let svg: String
        /// The target rendering size in points.
        let size: CGSize
    }

    /// Pre-processes a MathJax SVG for SwiftDraw rendering.
    ///
    /// - Parameters:
    ///   - svg: Raw SVG string from MathJaxSwift (uses `ex` units and `currentColor`).
    ///   - fontXHeight: The x-height of the target font in points.
    ///   - textColor: Optional hex color string (e.g. "#000000") to replace `currentColor`.
    /// - Returns: A `Result` with the processed SVG and the target point size.
    static func preprocess(svg: String, fontXHeight: CGFloat, textColor: String?) -> Result {
        var result = svg

        // 1. Extract ex dimensions to compute target point size
        let pointWidth = exValue(from: result, attribute: "width").map { CGFloat($0) * fontXHeight } ?? 0
        let pointHeight = exValue(from: result, attribute: "height").map { CGFloat($0) * fontXHeight } ?? 0

        // 2. Extract viewBox dimensions and use them as width/height for 1:1 coordinate mapping.
        //    This avoids integer truncation issues in SwiftDraw's DOM parser (DOM.Length is Int).
        //    We then use SVG.sized() to scale to the exact point dimensions.
        let vb = viewBoxDimensions(from: result)
        if let vbWidth = vb?.width, let vbHeight = vb?.height {
            result = replaceExAttribute(in: result, attribute: "width", with: "\(vbWidth)")
            result = replaceExAttribute(in: result, attribute: "height", with: "\(vbHeight)")
        }

        // 3. Replace currentColor with actual hex color
        if let textColor {
            result = result.replacingOccurrences(of: "currentColor", with: textColor)
        }

        // 4. Remove style attribute (vertical-align is for HTML embedding, not SVG rendering)
        result = result.replacingOccurrences(
            of: #" style="[^"]*""#,
            with: "",
            options: .regularExpression
        )

        return Result(svg: result, size: CGSize(width: pointWidth, height: pointHeight))
    }

    // MARK: - Private Helpers

    /// Extracts the numeric `ex` value for a given attribute (e.g. `width="2.127ex"` → 2.127).
    private static func exValue(from svg: String, attribute: String) -> Double? {
        let pattern = "\(attribute)=\"([\\d.]+)ex\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
              let valueRange = Range(match.range(at: 1), in: svg) else {
            return nil
        }
        return Double(svg[valueRange])
    }

    /// Extracts width and height from the viewBox attribute.
    /// viewBox="minX minY width height"
    private static func viewBoxDimensions(from svg: String) -> (width: Int, height: Int)? {
        let pattern = #"viewBox="[^\s"]+\s+[^\s"]+\s+([^\s"]+)\s+([^\s"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
              let wRange = Range(match.range(at: 1), in: svg),
              let hRange = Range(match.range(at: 2), in: svg),
              let w = Double(svg[wRange]),
              let h = Double(svg[hRange]) else {
            return nil
        }
        return (Int(ceil(w)), Int(ceil(h)))
    }

    /// Replaces `attribute="Xex"` with `attribute="value"`.
    private static func replaceExAttribute(in svg: String, attribute: String, with value: String) -> String {
        svg.replacingOccurrences(
            of: "\(attribute)=\"[\\d.]+ex\"",
            with: "\(attribute)=\"\(value)\"",
            options: .regularExpression
        )
    }
}
