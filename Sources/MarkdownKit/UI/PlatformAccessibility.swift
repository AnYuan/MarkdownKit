import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A cross-platform helper struct to easily extract standard accessibility
/// roles and string representations from a given `LayoutResult`.
///
/// The expensive work — checkbox enumeration, role-hint derivation — happens
/// once on the background layout thread in `LayoutResult.accessibility`.
/// This struct just maps those cached values into platform-specific traits.
public struct PlatformAccessibility {

    public static func accessibilityLabel(for layout: LayoutResult) -> String? {
        layout.accessibility.label
    }

    public static func accessibilityValue(for layout: LayoutResult) -> String? {
        layout.accessibility.value
    }

    public static func accessibilityHint(for layout: LayoutResult) -> String? {
        layout.accessibility.hint
    }

    #if canImport(UIKit)
    public static func accessibilityTraits(for layout: LayoutResult) -> UIAccessibilityTraits {
        var traits: UIAccessibilityTraits = .staticText
        switch layout.accessibility.nodeRoleHint {
        case .details, .link:
            traits.insert(.button)
        case .image:
            traits.insert(.image)
        case .staticText, .codeBlock, .table, .math:
            break
        }
        return traits
    }
    #endif

    #if canImport(AppKit)
    public static func accessibilityRole(for layout: LayoutResult) -> NSAccessibility.Role {
        switch layout.accessibility.nodeRoleHint {
        case .details:
            return .button
        case .codeBlock, .table:
            return .group
        case .staticText, .link, .image, .math:
            return .staticText
        }
    }
    #endif
}
