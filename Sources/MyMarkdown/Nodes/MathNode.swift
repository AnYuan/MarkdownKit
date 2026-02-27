import Foundation
import Markdown

/// A node representing LaTeX mathematical equations, ensuring ChatGPT parity (`$$` or `$`).
public struct MathNode: MarkdownNode {
    public let id = UUID()
    public let range: SourceRange?
    
    /// The style of the math equation (e.g., block vs inline).
    public enum Style {
        case block // e.g. $$ E = mc^2 $$
        case inline // e.g. $ E = mc^2 $
    }
    
    public let style: Style
    
    /// The raw LaTeX equation content to be evaluated.
    public let equation: String

    /// Convenience accessor used by LayoutSolver for baseline alignment.
    public var isInline: Bool { style == .inline }

    public var children: [MarkdownNode] {
        return [] // Math nodes evaluate raw mathematical strings, no children
    }
    
    public init(range: SourceRange?, style: Style, equation: String) {
        self.range = range
        self.style = style
        self.equation = equation
    }
}
