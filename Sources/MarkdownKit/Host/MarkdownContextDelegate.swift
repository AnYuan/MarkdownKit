import Foundation

/// Resolves GitHub-style autolinks into host-specific destinations.
///
/// Resolution can run off-main during detached parse/layout work. Stateful
/// resolvers must be thread-safe and include output-affecting configuration in
/// `cacheFingerprint(into:)`. Main-actor UI objects should delegate to a
/// dedicated immutable or explicitly synchronized resolver.
public protocol MarkdownAutolinkResolver: AnyObject, Sendable {
    /// Resolves a mention token like `@username`.
    func resolveMention(username: String) -> URL?

    /// Resolves an issue/PR token like `#123` or `owner/repo#123`.
    func resolveReference(reference: String) -> URL?

    /// Resolves a commit token like `1a2b3c4`.
    func resolveCommit(sha: String) -> URL?

    /// Mixes configuration that changes resolved output into `hasher`.
    func cacheFingerprint(into hasher: inout Hasher)
}

public extension MarkdownAutolinkResolver {
    func resolveMention(username: String) -> URL? { nil }
    func resolveReference(reference: String) -> URL? { nil }
    func resolveCommit(sha: String) -> URL? { nil }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
    }
}

@available(
    *,
    deprecated,
    renamed: "MarkdownAutolinkResolver",
    message: "Use MarkdownAutolinkResolver; conformers must satisfy its Sendable contract."
)
public typealias MarkdownContextDelegate = MarkdownAutolinkResolver
