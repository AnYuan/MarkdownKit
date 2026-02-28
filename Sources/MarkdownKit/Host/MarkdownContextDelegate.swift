import Foundation
import Markdown

/// A delegate protocol that allows the host application to provide business logic
/// and interaction handling for advanced Markdown features (like GitHub Flavored Markdown)
/// without the rendering engine needing to know about the host's backend architecture.
public protocol MarkdownContextDelegate: AnyObject {
    
    // MARK: - Autolink Resolution
    
    /// Resolves a GitHub-style user mention (e.g. `@username`) into an actionable URL.
    /// - Parameter username: The username parsed from the text, excluding the `@` symbol.
    /// - Returns: A URL pointing to the user's profile, or nil if mentions are unsupported.
    func resolveMention(username: String) -> URL?
    
    /// Resolves a GitHub-style issue or pull request reference (e.g. `#123` or `owner/repo#123`).
    /// - Parameter reference: The reference string parsed from the text.
    /// - Returns: A URL pointing to the issue/PR, or nil if references are unsupported.
    func resolveReference(reference: String) -> URL?
    
    /// Resolves a Git commit SHA (e.g. `a1b2c3d`) into an actionable URL.
    /// - Parameter sha: The parsed hexadecimal commit hash.
    /// - Returns: A URL pointing to the commit diff, or nil if SHAs are unsupported.
    func resolveCommit(sha: String) -> URL?
    
    // MARK: - Task List Interaction
    
    /// Invoked when a user interacts with a rendered checkbox (`- [ ]` or `- [x]`).
    /// - Parameters:
    ///   - isChecked: The new boolean state of the checkbox after the interaction.
    ///   - range: The source text range in the original markdown document corresponding to the list item.
    ///            The host app can use this range to mutate the source text and re-render.
    func didToggleCheckbox(isChecked: Bool, at range: SourceRange)
    
    // MARK: - Custom Actions
    
    /// Invoked when a user interacts with a custom action or permalink snippet.
    /// - Parameter actionID: An identifier representing the host-specific action.
    func didTriggerAction(withID actionID: String)
    
    // MARK: - Host Integrations
    
    /// Requests the host application to handle an attachment workflow (e.g., uploading a dropped image).
    /// - Parameters:
    ///   - localFile: The incoming local URL of the file to attach.
    ///   - completion: A closure the host calls with the finalized remote URL to insert into the markdown.
    func requestAttachmentUpload(for localFile: URL, completion: @escaping (URL?) -> Void)
    
    /// Invoked when the renderer detects semantic issue keywords (e.g. `Resolves #123`).
    /// - Parameters:
    ///   - keyword: The semantic keyword (like "Fixes", "Closes", "Resolves").
    ///   - reference: The issue reference (like "#123").
    func didDetectIssueKeyword(_ keyword: String, reference: String)
}

public extension MarkdownContextDelegate {
    // Provide default empty implementations to make these methods optional for host apps.
    func resolveMention(username: String) -> URL? { return nil }
    func resolveReference(reference: String) -> URL? { return nil }
    func resolveCommit(sha: String) -> URL? { return nil }
    func didToggleCheckbox(isChecked: Bool, at range: SourceRange) {}
    func didTriggerAction(withID actionID: String) {}
    func requestAttachmentUpload(for localFile: URL, completion: @escaping (URL?) -> Void) {}
    func didDetectIssueKeyword(_ keyword: String, reference: String) {}
}
