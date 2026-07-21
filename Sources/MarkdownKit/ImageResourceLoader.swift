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

private func imageDataValidationError(
    _ data: Data,
    policy: ImageLoadingPolicy
) -> ImageResourceLoadingError? {
    guard !data.isEmpty else {
        return .emptyData
    }
    guard policy.allowsDataCount(data.count) else {
        return .dataTooLarge(data.count)
    }
    return nil
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

private typealias ImageResourceContinuation =
    CheckedContinuation<LoadedImageResource, any Error>

private struct ImageResourceRequestCompletion {
    let taskIdentifier: Int?
    let task: URLSessionDataTask?
    let continuation: ImageResourceContinuation?
    let result: Result<LoadedImageResource, any Error>

    func resume() {
        guard let continuation else { return }
        switch result {
        case let .success(resource):
            continuation.resume(returning: resource)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

private enum ImageResourceResponseDecision {
    case allow
    case reject(ImageResourceRequestCompletion?)
    case ignore
}

private enum ImageResourceContinuationInstallation {
    case ready
    case completed(ImageResourceRequestCompletion)
}

private final class ImageResourceRequestState: @unchecked Sendable {
    let policy: ImageLoadingPolicy

    private let lock = NSLock()
    private weak var task: URLSessionDataTask?
    private var taskIdentifier: Int?
    private var continuation: ImageResourceContinuation?
    private var pendingResult: Result<LoadedImageResource, any Error>?
    private var isCompleted = false
    private var acceptedResponseURL: URL?
    private var data = Data()

    init(policy: ImageLoadingPolicy) {
        self.policy = policy
    }

    func attach(task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        taskIdentifier = task.taskIdentifier
        lock.unlock()
    }

    func install(
        continuation: ImageResourceContinuation
    ) -> ImageResourceContinuationInstallation {
        lock.lock()
        defer { lock.unlock() }

        if let pendingResult {
            self.pendingResult = nil
            return .completed(
                ImageResourceRequestCompletion(
                    taskIdentifier: taskIdentifier,
                    task: task,
                    continuation: continuation,
                    result: pendingResult
                )
            )
        }

        self.continuation = continuation
        return .ready
    }

    func receive(response: URLResponse) -> ImageResourceResponseDecision {
        lock.lock()
        defer { lock.unlock() }

        guard !isCompleted else {
            return .ignore
        }

        guard let finalURL = response.url else {
            return .reject(finishLocked(.failure(ImageResourceLoadingError.invalidResponse)))
        }

        let finalSource = ResolvedImageSource(url: finalURL, isRelativeFilePath: false)
        guard policy.allows(finalSource) else {
            return .reject(
                finishLocked(
                    .failure(ImageResourceLoadingError.redirectedSourceNotAllowed(finalURL))
                )
            )
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            return .reject(
                finishLocked(
                    .failure(
                        ImageResourceLoadingError.unacceptableStatusCode(
                            httpResponse.statusCode
                        )
                    )
                )
            )
        }

        if response.expectedContentLength >= 0,
           !policy.allowsByteCount(response.expectedContentLength) {
            return .reject(
                finishLocked(
                    .failure(
                        ImageResourceLoadingError.responseTooLarge(
                            response.expectedContentLength
                        )
                    )
                )
            )
        }

        if let mimeType = response.mimeType?.lowercased(),
           !mimeType.hasPrefix("image/") {
            return .reject(
                finishLocked(
                    .failure(ImageResourceLoadingError.unsupportedMIMEType(mimeType))
                )
            )
        }

        acceptedResponseURL = finalURL
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        return .allow
    }

    func receive(data chunk: Data) -> ImageResourceRequestCompletion? {
        lock.lock()
        defer { lock.unlock() }

        guard !isCompleted else { return nil }
        guard acceptedResponseURL != nil else {
            return finishLocked(.failure(ImageResourceLoadingError.invalidResponse))
        }

        let remainingCapacity = policy.maximumResponseBytes - data.count
        guard chunk.count <= remainingCapacity else {
            let firstInvalidCount = policy.maximumResponseBytes == Int.max
                ? Int.max
                : policy.maximumResponseBytes + 1
            return finishLocked(
                .failure(ImageResourceLoadingError.dataTooLarge(firstInvalidCount))
            )
        }

        data.append(chunk)
        return nil
    }

    func finish(with error: any Error) -> ImageResourceRequestCompletion? {
        lock.lock()
        defer { lock.unlock() }
        return finishLocked(.failure(error))
    }

    func finishSuccessfully() -> ImageResourceRequestCompletion? {
        lock.lock()
        defer { lock.unlock() }

        guard !isCompleted else { return nil }
        guard let acceptedResponseURL else {
            return finishLocked(.failure(ImageResourceLoadingError.invalidResponse))
        }
        if let validationError = imageDataValidationError(data, policy: policy) {
            return finishLocked(.failure(validationError))
        }

        return finishLocked(
            .success(LoadedImageResource(url: acceptedResponseURL, data: data))
        )
    }

    private func finishLocked(
        _ result: Result<LoadedImageResource, any Error>
    ) -> ImageResourceRequestCompletion? {
        guard !isCompleted else { return nil }
        isCompleted = true

        let continuation = continuation
        self.continuation = nil
        if continuation == nil {
            pendingResult = result
        }

        return ImageResourceRequestCompletion(
            taskIdentifier: taskIdentifier,
            task: task,
            continuation: continuation,
            result: result
        )
    }
}

private final class ImageResourceRequestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [Int: ImageResourceRequestState] = [:]

    func register(_ state: ImageResourceRequestState, for taskIdentifier: Int) {
        lock.lock()
        requests[taskIdentifier] = state
        lock.unlock()
    }

    func state(for taskIdentifier: Int) -> ImageResourceRequestState? {
        lock.lock()
        defer { lock.unlock() }
        return requests[taskIdentifier]
    }

    func remove(
        _ state: ImageResourceRequestState,
        for taskIdentifier: Int?
    ) {
        guard let taskIdentifier else { return }
        lock.lock()
        if requests[taskIdentifier] === state {
            requests.removeValue(forKey: taskIdentifier)
        }
        lock.unlock()
    }

    func removeAll() -> [ImageResourceRequestState] {
        lock.lock()
        let states = Array(requests.values)
        requests.removeAll()
        lock.unlock()
        return states
    }
}

private func completeImageResourceRequest(
    _ completion: ImageResourceRequestCompletion?,
    state: ImageResourceRequestState,
    registry: ImageResourceRequestRegistry,
    cancelTask: Bool
) {
    guard let completion else { return }
    registry.remove(state, for: completion.taskIdentifier)
    if cancelTask {
        completion.task?.cancel()
    }
    completion.resume()
}

private final class ImageResourceSessionDelegate:
    NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    private let registry: ImageResourceRequestRegistry

    init(registry: ImageResourceRequestRegistry) {
        self.registry = registry
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let state = registry.state(for: task.taskIdentifier) else {
            completionHandler(nil)
            return
        }
        guard let redirectedURL = request.url else {
            let completion = state.finish(with: ImageResourceLoadingError.invalidResponse)
            completionHandler(nil)
            completeImageResourceRequest(
                completion,
                state: state,
                registry: registry,
                cancelTask: true
            )
            return
        }

        let redirectedSource = ResolvedImageSource(
            url: redirectedURL,
            isRelativeFilePath: false
        )
        guard state.policy.allows(redirectedSource) else {
            let completion = state.finish(
                with: ImageResourceLoadingError.redirectedSourceNotAllowed(redirectedURL)
            )
            completionHandler(nil)
            completeImageResourceRequest(
                completion,
                state: state,
                registry: registry,
                cancelTask: true
            )
            return
        }

        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let state = registry.state(for: dataTask.taskIdentifier) else {
            completionHandler(.cancel)
            return
        }

        switch state.receive(response: response) {
        case .allow:
            completionHandler(.allow)
        case let .reject(completion):
            completionHandler(.cancel)
            completeImageResourceRequest(
                completion,
                state: state,
                registry: registry,
                cancelTask: true
            )
        case .ignore:
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let state = registry.state(for: dataTask.taskIdentifier) else {
            dataTask.cancel()
            return
        }
        completeImageResourceRequest(
            state.receive(data: data),
            state: state,
            registry: registry,
            cancelTask: true
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let state = registry.state(for: task.taskIdentifier) else {
            return
        }

        let completion: ImageResourceRequestCompletion?
        if let error {
            completion = state.finish(with: error)
        } else {
            completion = state.finishSuccessfully()
        }
        completeImageResourceRequest(
            completion,
            state: state,
            registry: registry,
            cancelTask: false
        )
    }
}

private final class ImageResourceTransport: Sendable {
    private let registry: ImageResourceRequestRegistry
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        let registry = ImageResourceRequestRegistry()
        self.registry = registry
        session = URLSession(
            configuration: configuration,
            delegate: ImageResourceSessionDelegate(registry: registry),
            delegateQueue: nil
        )
    }

    deinit {
        for state in registry.removeAll() {
            let completion = state.finish(with: CancellationError())
            completion?.task?.cancel()
            completion?.resume()
        }
        session.invalidateAndCancel()
    }

    func load(
        request: URLRequest,
        policy: ImageLoadingPolicy
    ) async throws -> LoadedImageResource {
        let state = ImageResourceRequestState(policy: policy)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = self.session.dataTask(with: request)
                state.attach(task: task)
                self.registry.register(state, for: task.taskIdentifier)

                switch state.install(continuation: continuation) {
                case .ready:
                    guard !Task.isCancelled else {
                        completeImageResourceRequest(
                            state.finish(with: CancellationError()),
                            state: state,
                            registry: self.registry,
                            cancelTask: true
                        )
                        return
                    }
                    task.resume()
                case let .completed(completion):
                    completeImageResourceRequest(
                        completion,
                        state: state,
                        registry: self.registry,
                        cancelTask: true
                    )
                }
            }
        } onCancel: {
            completeImageResourceRequest(
                state.finish(with: CancellationError()),
                state: state,
                registry: self.registry,
                cancelTask: true
            )
        }
    }
}

struct ImageResourceLoader: Sendable {
    static let shared = ImageResourceLoader()

    private let transport: ImageResourceTransport

    init(urlSession: URLSession = .shared) {
        let configuration = urlSession.configuration
        let snapshot = configuration.copy() as? URLSessionConfiguration ?? configuration
        transport = ImageResourceTransport(configuration: snapshot)
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
        if let validationError = imageDataValidationError(data, policy: policy) {
            throw validationError
        }
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
        return try await transport.load(request: request, policy: policy)
    }

}
