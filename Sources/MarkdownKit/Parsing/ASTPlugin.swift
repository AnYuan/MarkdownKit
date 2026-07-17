import Foundation

/// A protocol defining a middleware plugin that can inspect or modify the AST
/// before it is sent to the Layout Engine.
///
/// This provides extreme extensibility. For instance, a plugin could search for
/// `TextNode` objects containing `$$` and replace them with `MathNode` objects,
/// or find specific syntax like `[ ]` to create Task List Checkboxes.
public protocol ASTPlugin {
    /// Mutates the given collection of `MarkdownNode` elements.
    ///
    /// - Parameter nodes: The current array of sibling nodes.
    /// - Returns: The modified array of nodes after the plugin has executed its transformations.
    func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode]

    /// Mixes configuration that changes this plugin's output into `hasher`.
    ///
    /// Stateless plugins can use the default type-based implementation. Stateful
    /// plugins should override this method so live SwiftUI views rerender when
    /// their configuration changes.
    func cacheFingerprint(into hasher: inout Hasher)
}

public extension ASTPlugin {
    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
    }
}

enum ASTPluginFingerprint {
    static func make(for plugins: [ASTPlugin]) -> Int {
        var hasher = Hasher()
        hasher.combine(plugins.count)
        for plugin in plugins {
            plugin.cacheFingerprint(into: &hasher)
        }
        return hasher.finalize()
    }
}
