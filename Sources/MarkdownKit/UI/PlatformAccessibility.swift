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
    enum AppKitValue: Equatable {
        case text(String)
        case number(Int)
    }

    struct AppKitProjection {
        let role: NSAccessibility.Role
        let label: String?
        let value: AppKitValue?
        let help: String?
    }

    static func appKitProjection(for layout: LayoutResult) -> AppKitProjection {
        let metadata = layout.accessibility
        let role: NSAccessibility.Role
        let value: AppKitValue?

        switch metadata.taskCheckboxState {
        case .checked:
            role = .checkBox
            value = .number(1)
        case .unchecked:
            role = .checkBox
            value = .number(0)
        case .none:
            switch metadata.nodeRoleHint {
            case .details:
                role = .button
                value = metadata.value.map(AppKitValue.text)
            case .codeBlock, .table:
                role = .group
                value = metadata.value.map(AppKitValue.text)
            case .staticText, .link, .image, .math:
                role = .staticText
                value = metadata.value.map(AppKitValue.text)
            }
        }

        return AppKitProjection(
            role: role,
            label: metadata.label,
            value: value,
            help: metadata.hint
        )
    }

    public static func accessibilityRole(for layout: LayoutResult) -> NSAccessibility.Role {
        appKitProjection(for: layout).role
    }
    #endif
}
