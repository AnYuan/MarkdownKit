//
//  ImageLoadingPolicy.swift
//  MarkdownKit
//

import Foundation

/// Host-controlled rules for loading Markdown image sources.
///
/// The default policy is intentionally conservative for untrusted Markdown:
/// it performs no image I/O and falls back to alt text. Hosts can opt into
/// HTTPS-only remote loading or trusted local loading per rendering surface.
public struct ImageLoadingPolicy: Sendable, Equatable {
    public let allowedRemoteSchemes: Set<String>
    public let allowsLocalFileURLs: Bool
    public let allowsRelativeFilePaths: Bool
    public let maximumResponseBytes: Int

    public init(
        allowedRemoteSchemes: Set<String> = [],
        allowsLocalFileURLs: Bool = false,
        allowsRelativeFilePaths: Bool = false,
        maximumResponseBytes: Int = 8 * 1024 * 1024
    ) {
        self.allowedRemoteSchemes = Set(allowedRemoteSchemes.map { $0.lowercased() })
        self.allowsLocalFileURLs = allowsLocalFileURLs
        self.allowsRelativeFilePaths = allowsRelativeFilePaths
        self.maximumResponseBytes = max(0, maximumResponseBytes)
    }

    public static let `default` = ImageLoadingPolicy()

    /// Allows HTTPS remote images with local file access still denied.
    public static let remoteHTTPS = ImageLoadingPolicy(
        allowedRemoteSchemes: ["https"],
        allowsLocalFileURLs: false,
        allowsRelativeFilePaths: false,
        maximumResponseBytes: 8 * 1024 * 1024
    )

    /// Allows local, relative, HTTP, and HTTPS image sources. Use only for
    /// Markdown that already belongs to the host app or a trusted user.
    public static let trusted = ImageLoadingPolicy(
        allowedRemoteSchemes: ["http", "https"],
        allowsLocalFileURLs: true,
        allowsRelativeFilePaths: true,
        maximumResponseBytes: 16 * 1024 * 1024
    )

    /// Blocks every image source and always falls back to alt text.
    public static let disabled = ImageLoadingPolicy(
        allowedRemoteSchemes: [],
        allowsLocalFileURLs: false,
        allowsRelativeFilePaths: false,
        maximumResponseBytes: 0
    )
}

extension ImageLoadingPolicy {
    var cacheFingerprint: Int {
        var hasher = Hasher()
        for scheme in allowedRemoteSchemes.sorted() {
            hasher.combine(scheme)
        }
        hasher.combine(allowsLocalFileURLs)
        hasher.combine(allowsRelativeFilePaths)
        hasher.combine(maximumResponseBytes)
        return hasher.finalize()
    }

    func allows(_ source: ResolvedImageSource) -> Bool {
        if source.url.isFileURL {
            return allowsLocalFileURLs && (!source.isRelativeFilePath || allowsRelativeFilePaths)
        }

        guard let scheme = source.url.scheme?.lowercased() else {
            return false
        }
        return allowedRemoteSchemes.contains(scheme)
    }

    func allowsByteCount(_ byteCount: Int64) -> Bool {
        guard byteCount >= 0 else { return true }
        return byteCount <= Int64(maximumResponseBytes)
    }

    func allowsDataCount(_ count: Int) -> Bool {
        allowsByteCount(Int64(count))
    }
}

struct ResolvedImageSource: Sendable {
    let url: URL
    let isRelativeFilePath: Bool
}

enum ImageSourceResolver {
    static func resolve(_ source: String) -> ResolvedImageSource? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return ResolvedImageSource(url: url, isRelativeFilePath: false)
        }

        // If it looks like a URL but failed parsing, do not reinterpret it as a local file path.
        if trimmed.contains("://") {
            return nil
        }

        if trimmed.hasPrefix("~/") {
            let expandedPath = (trimmed as NSString).expandingTildeInPath
            return ResolvedImageSource(url: URL(fileURLWithPath: expandedPath), isRelativeFilePath: false)
        }

        if trimmed.hasPrefix("/") {
            return ResolvedImageSource(url: URL(fileURLWithPath: trimmed), isRelativeFilePath: false)
        }

        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(trimmed)
        return ResolvedImageSource(url: url, isRelativeFilePath: true)
    }
}
