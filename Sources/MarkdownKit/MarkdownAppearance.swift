//
//  MarkdownAppearance.swift
//  MarkdownKit
//

/// A platform-neutral appearance selector for explicit light/dark layout.
///
/// Pass `MarkdownAppearance` to `LayoutSolver` to produce appearance-aware
/// layouts without reading `UITraitCollection.current`, `NSAppearance.current`,
/// or any other ambient appearance state. All color resolution uses the
/// supplied explicit value, making the layout pipeline safe for off-main work.
public enum MarkdownAppearance: Sendable, Hashable {
    case light
    case dark
}
