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

    /// Task-list state used by platform adapters to expose native checkbox
    /// semantics without re-scanning the rendered attributed string.
    public let taskCheckboxState: CheckboxState

    public init(
        label: String?,
        value: String?,
        hint: String?,
        nodeRoleHint: NodeRoleHint,
        taskCheckboxState: CheckboxState = .none
    ) {
        self.label = label
        self.value = value
        self.hint = hint
        self.nodeRoleHint = nodeRoleHint
        self.taskCheckboxState = taskCheckboxState
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
        let taskCheckboxState: CheckboxState

        switch node {
        case let details as DetailsNode:
            let summaryText = (details.summary?.children.first as? TextNode)?.text ?? "Details"
            label = "Collapsible Section: \(summaryText)"
            value = details.isOpen ? "Expanded" : "Collapsed"
            hint = "Double-tap to expand or collapse"
            role = .details
            taskCheckboxState = .none
        case let math as MathNode:
            label = "Math Equation: \(math.equation)"
            value = nil
            hint = nil
            role = .math
            taskCheckboxState = .none
        case let image as ImageNode:
            label = "Image: \(image.altText ?? image.source ?? "Attachment")"
            value = nil
            hint = nil
            role = .image
            taskCheckboxState = .none
        case let listItem as ListItemNode where listItem.checkbox != .none:
            taskCheckboxState = listItem.checkbox
            label = attributedString?.string
            value = checkboxValue(for: taskCheckboxState)
            hint = nil
            role = .staticText
        case is LinkNode:
            label = attributedString?.string
            value = nil
            hint = "Double-tap to open link"
            role = .link
            taskCheckboxState = .none
        case is CodeBlockNode, is DiagramNode:
            label = attributedString?.string
            value = nil
            hint = nil
            role = .codeBlock
            taskCheckboxState = .none
        case is TableNode:
            label = attributedString?.string
            value = nil
            hint = nil
            role = .table
            taskCheckboxState = .none
        default:
            taskCheckboxState = scanCheckboxState(in: attributedString)
            label = attributedString?.string
            value = checkboxValue(for: taskCheckboxState)
            hint = nil
            role = .staticText
        }

        return AccessibilityMetadata(
            label: label,
            value: value,
            hint: hint,
            nodeRoleHint: role,
            taskCheckboxState: taskCheckboxState
        )
    }

    /// Single `enumerateAttribute(.markdownCheckbox, …)` pass executed at
    /// layout time. Cells consuming the metadata never re-walk the string.
    private static func scanCheckboxState(in attributedString: NSAttributedString?) -> CheckboxState {
        guard let attributedString else { return .none }
        var checkboxState = CheckboxState.none
        attributedString.enumerateAttribute(
            .markdownCheckbox,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, _, stop in
            if let data = value as? CheckboxInteractionData {
                checkboxState = data.isChecked ? .checked : .unchecked
                stop.pointee = true
            }
        }
        return checkboxState
    }

    private static func checkboxValue(for state: CheckboxState) -> String? {
        switch state {
        case .checked:
            return "Checked"
        case .unchecked:
            return "Unchecked"
        case .none:
            return nil
        }
    }
}
