import Foundation

/// Protocol for pluggable math rendering, following the `DiagramRenderingAdapter` pattern.
///
/// Conformers convert a `MathNode` into a rich `NSAttributedString` (typically containing
/// an `NSTextAttachment` with a rasterized image). The library ships a default WebKit-based
/// implementation; host apps can inject their own adapter via `LayoutSolver.init(mathAdapter:)`.
public protocol MathRenderingAdapter: Sendable {
    /// Asynchronously renders a math node into an attributed string.
    func render(from node: MathNode, theme: Theme) async -> NSAttributedString
    /// Synchronously renders using cached results. Used by the sync layout path.
    func renderSync(from node: MathNode, theme: Theme) -> NSAttributedString
}
