import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A cross-platform helper struct to easily extract standard accessibility 
/// roles and string representations from a given `LayoutResult`.
public struct PlatformAccessibility {
    
    /// Returns the descriptive text value (the spoken text) for a given layout node.
    public static func accessibilityLabel(for layout: LayoutResult) -> String? {
        if let details = layout.node as? DetailsNode {
            return "Collapsible Section: \((details.summary?.children.first as? TextNode)?.text ?? "Details")"
        }
        
        if let math = layout.node as? MathNode {
            return "Math Equation: \(math.equation)"
        }
        
        if let image = layout.node as? ImageNode {
            return "Image: \(image.altText ?? image.source ?? "Attachment")"
        }
        
        // General text fallback
        return layout.attributedString?.string
    }
    
    /// Returns a generic value string for states like "Expanded" or "Collapsed".
    public static func accessibilityValue(for layout: LayoutResult) -> String? {
        if let details = layout.node as? DetailsNode {
            return details.isOpen ? "Expanded" : "Collapsed"
        }
        if let checkbox = layout.node as? ListItemNode, checkbox.checkbox != .none {
            return checkbox.checkbox == .checked ? "Checked" : "Unchecked"
        }
        // General text might contain checkbox interactivity as attributes
        if let attrString = layout.attributedString {
            var isTask = false
            var isChecked = false
            attrString.enumerateAttribute(.markdownCheckbox, in: NSRange(location: 0, length: attrString.length), options: []) { value, range, stop in
                if let data = value as? CheckboxInteractionData {
                    isTask = true
                    isChecked = data.isChecked
                    stop.pointee = true
                }
            }
            if isTask {
                return isChecked ? "Checked" : "Unchecked"
            }
        }
        
        return nil
    }
    
    #if canImport(UIKit)
    /// Returns the corresponding UIAccessibilityTraits for iOS.
    public static func accessibilityTraits(for layout: LayoutResult) -> UIAccessibilityTraits {
        var traits: UIAccessibilityTraits = .staticText
        
        if layout.node is DetailsNode || layout.node is LinkNode {
            traits.insert(.button)
        } else if layout.node is ImageNode {
            traits.insert(.image)
        }
        
        return traits
    }
    #endif
    
    #if canImport(AppKit)
    /// Returns the corresponding NSAccessibility.Role for macOS.
    public static func accessibilityRole(for layout: LayoutResult) -> NSAccessibility.Role {
        if layout.node is DetailsNode { return .button }
        if layout.node is CodeBlockNode || layout.node is DiagramNode { return .group }
        if layout.node is TableNode { return .group }
        return .staticText // default
    }
    #endif
}
