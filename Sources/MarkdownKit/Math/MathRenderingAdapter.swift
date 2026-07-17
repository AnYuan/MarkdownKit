import Foundation

/// Protocol for pluggable math rendering, following the `DiagramRenderingAdapter` pattern.
///
/// Conformers convert a `MathNode` into a rich `NSAttributedString` (typically containing
/// an `NSTextAttachment` with a rasterized image). The library ships a default WebKit-based
/// implementation; host apps can inject their own adapter via `LayoutSolver.init(mathAdapter:)`.
public protocol MathRenderingAdapter: Sendable {
    /// Asynchronously renders a math node into an attributed string.
    /// - Parameter contextFont: The font of the surrounding text context (e.g. heading font).
    ///   When `nil`, the adapter should fall back to `theme.typography.paragraph.font`.
    func render(from node: MathNode, theme: Theme, contextFont: Font?) async -> NSAttributedString
    /// Synchronously renders using cached results. Used by the sync layout path.
    func renderSync(from node: MathNode, theme: Theme, contextFont: Font?) -> NSAttributedString
    /// Mixes configuration that changes rendered output into `hasher`.
    func cacheFingerprint(into hasher: inout Hasher)
}

// Default implementations for backward compatibility with custom adapters.
public extension MathRenderingAdapter {
    func render(from node: MathNode, theme: Theme) async -> NSAttributedString {
        await render(from: node, theme: theme, contextFont: nil)
    }
    func renderSync(from node: MathNode, theme: Theme) -> NSAttributedString {
        renderSync(from: node, theme: theme, contextFont: nil)
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
    }
}
