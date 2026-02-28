import Foundation
import Markdown

public extension NSAttributedString.Key {
    /// A custom attribute key used to tag interactive checkbox prefixes in the layout.
    /// The value associated with this key should be a `CheckboxInteractionData` instance.
    static let markdownCheckbox = NSAttributedString.Key("MarkdownKit.Checkbox")
}

/// The data payload embedded in a `.markdownCheckbox` attribute.
public struct CheckboxInteractionData {
    public let isChecked: Bool
    public let range: SourceRange
    
    public init(isChecked: Bool, range: SourceRange) {
        self.isChecked = isChecked
        self.range = range
    }
}
