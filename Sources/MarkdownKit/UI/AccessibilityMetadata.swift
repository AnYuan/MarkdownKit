//
//  AccessibilityMetadata.swift
//  MarkdownKit
//
//  Pre-computed accessibility values cached on `LayoutResult` so the UI layer
//  doesn't re-walk the attributed string (for `markdownCheckbox` enumeration)
//  or re-derive role hints on every cell `configure`. Computed once on the
//  background layout thread; consumed on main during cell reuse.
//

import Foundation

public struct AccessibilityMetadata: Sendable {
    /// VoiceOver-spoken text. May be `nil` when the node has no spoken value
    /// (e.g. a `ThematicBreakNode`).
    public let label: String?

    /// Generic value string for states like "Expanded" / "Checked".
    public let value: String?

    /// VoiceOver hint describing the interaction model, if any.
    public let hint: String?

    /// Stable, platform-agnostic role discriminator. `PlatformAccessibility`
    /// translates this to `UIAccessibilityTraits` / `NSAccessibility.Role`.
    public enum NodeRoleHint: Sendable {
        case staticText
        case details
        case link
        case image
        case codeBlock
        case table
        case math
    }

    public let nodeRoleHint: NodeRoleHint

    public init(
        label: String?,
        value: String?,
        hint: String?,
        nodeRoleHint: NodeRoleHint
    ) {
        self.label = label
        self.value = value
        self.hint = hint
        self.nodeRoleHint = nodeRoleHint
    }
}

extension AccessibilityMetadata {
    /// Builds the metadata for a node + its rendered attributed string. Runs
    /// once at `LayoutResult.init` time so the UI layer gets `O(1)` access.
    /// The previously hot path was `accessibilityValue` walking
    /// `attributedString.enumerateAttribute(.markdownCheckbox, …)` on the main
    /// thread for every cell reconfigure — moved here, on the background
    /// layout thread.
    static func make(for node: MarkdownNode, attributedString: NSAttributedString?) -> AccessibilityMetadata {
        let label: String?
        let value: String?
        let hint: String?
        let role: NodeRoleHint

        switch node {
        case let details as DetailsNode:
            let summaryText = (details.summary?.children.first as? TextNode)?.text ?? "Details"
            label = "Collapsible Section: \(summaryText)"
            value = details.isOpen ? "Expanded" : "Collapsed"
            hint = "Double-tap to expand or collapse"
            role = .details
        case let math as MathNode:
            label = "Math Equation: \(math.equation)"
            value = nil
            hint = nil
            role = .math
        case let image as ImageNode:
            label = "Image: \(image.altText ?? image.source ?? "Attachment")"
            value = nil
            hint = nil
            role = .image
        case let listItem as ListItemNode where listItem.checkbox != .none:
            label = attributedString?.string
            value = listItem.checkbox == .checked ? "Checked" : "Unchecked"
            hint = nil
            role = .staticText
        case is LinkNode:
            label = attributedString?.string
            value = nil
            hint = "Double-tap to open link"
            role = .link
        case is CodeBlockNode, is DiagramNode:
            label = attributedString?.string
            value = nil
            hint = nil
            role = .codeBlock
        case is TableNode:
            label = attributedString?.string
            value = nil
            hint = nil
            role = .table
        default:
            label = attributedString?.string
            value = scanCheckboxValue(in: attributedString)
            hint = nil
            role = .staticText
        }

        return AccessibilityMetadata(
            label: label,
            value: value,
            hint: hint,
            nodeRoleHint: role
        )
    }

    /// Single `enumerateAttribute(.markdownCheckbox, …)` pass executed at
    /// layout time. Cells consuming the metadata never re-walk the string.
    private static func scanCheckboxValue(in attributedString: NSAttributedString?) -> String? {
        guard let attributedString else { return nil }
        var isTask = false
        var isChecked = false
        attributedString.enumerateAttribute(
            .markdownCheckbox,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, _, stop in
            if let data = value as? CheckboxInteractionData {
                isTask = true
                isChecked = data.isChecked
                stop.pointee = true
            }
        }
        guard isTask else { return nil }
        return isChecked ? "Checked" : "Unchecked"
    }
}
