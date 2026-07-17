import Foundation

private struct ResolvedImageSource: Sendable {
    let url: URL
    let isRelativeFilePath: Bool
}

private enum ImageSourceResolver {
    static func resolve(_ source: String) -> ResolvedImageSource? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return ResolvedImageSource(url: url, isRelativeFilePath: false)
        }

        // Never reinterpret a malformed URL-shaped value as a local path.
        if trimmed.contains("://") {
            return nil
        }

        if trimmed.hasPrefix("~/") {
            let expandedPath = (trimmed as NSString).expandingTildeInPath
            return ResolvedImageSource(
                url: URL(fileURLWithPath: expandedPath),
                isRelativeFilePath: false
            )
        }

        if trimmed.hasPrefix("/") {
            return ResolvedImageSource(
                url: URL(fileURLWithPath: trimmed),
                isRelativeFilePath: false
            )
        }

        let cwd = FileManager.default.currentDirectoryPath
        return ResolvedImageSource(
            url: URL(fileURLWithPath: cwd).appendingPathComponent(trimmed),
            isRelativeFilePath: true
        )
    }
}

private extension ImageLoadingPolicy {
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

private final class ImageRedirectPolicyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: ImageLoadingPolicy
    private let lock = NSLock()
    private var rejectedURL: URL?

    init(policy: ImageLoadingPolicy) {
        self.policy = policy
    }

    var rejectedRedirectURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return rejectedURL
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            return
        }

        let redirectedSource = ResolvedImageSource(url: url, isRelativeFilePath: false)
        guard policy.allows(redirectedSource) else {
            lock.lock()
            rejectedURL = url
            lock.unlock()
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

struct LoadedImageResource: Sendable {
    let url: URL
    let data: Data
}

enum ImageResourceLoadingError: Error, Equatable, Sendable {
    case invalidSource
    case sourceNotAllowed(URL)
    case redirectedSourceNotAllowed(URL)
    case invalidResponse
    case unacceptableStatusCode(Int)
    case responseTooLarge(Int64)
    case unsupportedMIMEType(String)
    case emptyData
    case dataTooLarge(Int)
}

struct ImageResourceLoader: Sendable {
    static let shared = ImageResourceLoader()

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    @concurrent
    func load(
        source: String,
        policy: ImageLoadingPolicy
    ) async throws -> LoadedImageResource {
        guard let resolved = ImageSourceResolver.resolve(source) else {
            throw ImageResourceLoadingError.invalidSource
        }
        guard policy.allows(resolved) else {
            throw ImageResourceLoadingError.sourceNotAllowed(resolved.url)
        }

        if resolved.url.isFileURL {
            return try loadFile(resolved, policy: policy)
        }

        return try await loadRemote(resolved, policy: policy)
    }

    private func loadFile(
        _ source: ResolvedImageSource,
        policy: ImageLoadingPolicy
    ) throws -> LoadedImageResource {
        let fileSize = try source.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let fileSize, !policy.allowsDataCount(fileSize) {
            throw ImageResourceLoadingError.responseTooLarge(Int64(fileSize))
        }

        let data = try Data(contentsOf: source.url)
        try validateFinalData(data, policy: policy)
        return LoadedImageResource(url: source.url, data: data)
    }

    private func loadRemote(
        _ source: ResolvedImageSource,
        policy: ImageLoadingPolicy
    ) async throws -> LoadedImageResource {
        let request = URLRequest(
            url: source.url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 12
        )
        let redirectDelegate = ImageRedirectPolicyDelegate(policy: policy)
        do {
            let (bytes, response) = try await urlSession.bytes(
                for: request,
                delegate: redirectDelegate
            )

            if let rejectedURL = redirectDelegate.rejectedRedirectURL {
                throw ImageResourceLoadingError.redirectedSourceNotAllowed(rejectedURL)
            }

            guard let finalURL = response.url else {
                throw ImageResourceLoadingError.invalidResponse
            }
            let finalSource = ResolvedImageSource(url: finalURL, isRelativeFilePath: false)
            guard policy.allows(finalSource) else {
                throw ImageResourceLoadingError.redirectedSourceNotAllowed(finalURL)
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw ImageResourceLoadingError.unacceptableStatusCode(httpResponse.statusCode)
            }

            if response.expectedContentLength >= 0,
               !policy.allowsByteCount(response.expectedContentLength) {
                throw ImageResourceLoadingError.responseTooLarge(response.expectedContentLength)
            }

            if let mimeType = response.mimeType?.lowercased(),
               !mimeType.hasPrefix("image/") {
                throw ImageResourceLoadingError.unsupportedMIMEType(mimeType)
            }

            var data = Data()
            if response.expectedContentLength > 0,
               response.expectedContentLength <= Int64(Int.max) {
                data.reserveCapacity(Int(response.expectedContentLength))
            }
            for try await byte in bytes {
                guard data.count < policy.maximumResponseBytes else {
                    throw ImageResourceLoadingError.dataTooLarge(data.count + 1)
                }
                data.append(byte)
            }

            try validateFinalData(data, policy: policy)
            return LoadedImageResource(url: finalURL, data: data)
        } catch {
            if let rejectedURL = redirectDelegate.rejectedRedirectURL {
                throw ImageResourceLoadingError.redirectedSourceNotAllowed(rejectedURL)
            }
            throw error
        }
    }

    private func validateFinalData(
        _ data: Data,
        policy: ImageLoadingPolicy
    ) throws {
        guard !data.isEmpty else {
            throw ImageResourceLoadingError.emptyData
        }
        guard policy.allowsDataCount(data.count) else {
            throw ImageResourceLoadingError.dataTooLarge(data.count)
        }
    }
}
