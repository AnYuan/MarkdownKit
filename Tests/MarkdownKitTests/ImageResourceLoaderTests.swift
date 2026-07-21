import Foundation
import XCTest
@testable import MarkdownKit

private struct StubbedURLResponse {
    let response: URLResponse
    let chunks: [Data]
    let completion: StubbedURLCompletion
    let bodyGate: StubbedURLGate?
    let responseTriggerData: Data?
    let finishesBeforeBody: Bool
    let deliversAfterStop: Bool

    init(
        response: URLResponse,
        chunks: [Data],
        completion: StubbedURLCompletion = .finish,
        bodyGate: StubbedURLGate? = nil,
        responseTriggerData: Data? = nil,
        finishesBeforeBody: Bool = false,
        deliversAfterStop: Bool = false
    ) {
        self.response = response
        self.chunks = chunks
        self.completion = completion
        self.bodyGate = bodyGate
        self.responseTriggerData = responseTriggerData
        self.finishesBeforeBody = finishesBeforeBody
        self.deliversAfterStop = deliversAfterStop
    }
}

private enum StubbedURLCompletion {
    case finish
    case failure(URLError)
    case none
}

private final class StubbedURLGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isOpen = false
    private var isWaiting = false

    func wait() {
        condition.lock()
        isWaiting = true
        condition.broadcast()
        while !isOpen {
            condition.wait()
        }
        condition.unlock()
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }

    func waitForWaiter(timeout: TimeInterval = 2) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while !isWaiting {
            guard condition.wait(until: deadline) else {
                return isWaiting
            }
        }
        return true
    }
}

private enum StubbedURLAction {
    case response(StubbedURLResponse)
    case redirect(response: HTTPURLResponse, request: URLRequest)
}

private struct SendableURLProtocolReference: @unchecked Sendable {
    let value: ImageLoaderURLProtocol
}

private final class ImageLoaderURLProtocolState: @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> StubbedURLAction

    private let condition = NSCondition()
    private var handler: Handler?
    private var requestCount = 0
    private var responseCounts: [URL: Int] = [:]
    private var stopCounts: [URL: Int] = [:]
    private var deliveredByteCounts: [URL: Int] = [:]
    private var workerCompletionCounts: [URL: Int] = [:]

    func configure(handler: @escaping Handler) {
        condition.lock()
        self.handler = handler
        requestCount = 0
        responseCounts.removeAll()
        stopCounts.removeAll()
        deliveredByteCounts.removeAll()
        workerCompletionCounts.removeAll()
        condition.unlock()
    }

    func reset() {
        condition.lock()
        handler = nil
        requestCount = 0
        responseCounts.removeAll()
        stopCounts.removeAll()
        deliveredByteCounts.removeAll()
        workerCompletionCounts.removeAll()
        condition.broadcast()
        condition.unlock()
    }

    func action(for request: URLRequest) throws -> StubbedURLAction {
        let handler: Handler?
        condition.lock()
        requestCount += 1
        handler = self.handler
        condition.broadcast()
        condition.unlock()

        guard let handler else {
            throw URLError(.resourceUnavailable)
        }
        return try handler(request)
    }

    func count() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return requestCount
    }

    func recordResponse(for url: URL) {
        condition.lock()
        responseCounts[url, default: 0] += 1
        condition.broadcast()
        condition.unlock()
    }

    func recordStop(for url: URL) {
        condition.lock()
        stopCounts[url, default: 0] += 1
        condition.broadcast()
        condition.unlock()
    }

    func recordDeliveredChunk(_ chunk: Data, for url: URL) {
        condition.lock()
        deliveredByteCounts[url, default: 0] += chunk.count
        condition.broadcast()
        condition.unlock()
    }

    func recordWorkerCompletion(for url: URL) {
        condition.lock()
        workerCompletionCounts[url, default: 0] += 1
        condition.broadcast()
        condition.unlock()
    }

    func deliveredByteCount(for url: URL) -> Int {
        condition.lock()
        defer { condition.unlock() }
        return deliveredByteCounts[url, default: 0]
    }

    func waitForDeliveredByteCount(
        _ minimumCount: Int,
        for url: URL
    ) -> Bool {
        waitUntil { deliveredByteCounts[url, default: 0] >= minimumCount }
    }

    func waitForResponse(for url: URL) -> Bool {
        waitUntil { responseCounts[url, default: 0] > 0 }
    }

    func waitForStop(for url: URL) -> Bool {
        waitUntil { stopCounts[url, default: 0] > 0 }
    }

    func waitForWorkerCompletion(for url: URL) -> Bool {
        waitUntil { workerCompletionCounts[url, default: 0] > 0 }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: () -> Bool
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }

        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard condition.wait(until: deadline) else {
                return predicate()
            }
        }
        return true
    }
}

private final class ImageLoaderURLProtocol: URLProtocol {
    static let state = ImageLoaderURLProtocolState()

    private let stopLock = NSLock()
    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            switch try Self.state.action(for: request) {
            case let .response(stub):
                guard let url = request.url else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                Self.state.recordResponse(for: url)
                client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
                if let bodyGate = stub.bodyGate {
                    if let responseTriggerData = stub.responseTriggerData {
                        Self.state.recordDeliveredChunk(responseTriggerData, for: url)
                        client?.urlProtocol(self, didLoad: responseTriggerData)
                    }
                    if stub.finishesBeforeBody {
                        client?.urlProtocolDidFinishLoading(self)
                    }
                    let reference = SendableURLProtocolReference(value: self)
                    DispatchQueue.global(qos: .userInitiated).async {
                        bodyGate.wait()
                        reference.value.deliver(stub, for: url)
                    }
                } else {
                    deliver(stub, for: url)
                }
            case let .redirect(response, request):
                client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        stopLock.lock()
        isStopped = true
        stopLock.unlock()
        if let url = request.url {
            Self.state.recordStop(for: url)
        }
    }

    private func deliver(_ stub: StubbedURLResponse, for url: URL) {
        defer { Self.state.recordWorkerCompletion(for: url) }

        for chunk in stub.chunks {
            guard stub.deliversAfterStop || !stopped else { return }
            Self.state.recordDeliveredChunk(chunk, for: url)
            client?.urlProtocol(self, didLoad: chunk)
        }

        guard stub.deliversAfterStop || !stopped else { return }
        switch stub.completion {
        case .finish:
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .none:
            break
        }
    }

    private var stopped: Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return isStopped
    }
}

final class ImageResourceLoaderTests: XCTestCase {
    override func tearDown() {
        ImageLoaderURLProtocol.state.reset()
        super.tearDown()
    }

    func testDenyAllPoliciesRejectBeforeNetworkIO() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }

        for policy in [ImageLoadingPolicy.default, .disabled] {
            await assertLoadingError(.sourceNotAllowed(try XCTUnwrap(URL(string: "https://example.com/image.png")))) {
                try await loader.load(source: "https://example.com/image.png", policy: policy)
            }
        }

        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 0)
    }

    func testRemoteHTTPSLoadsImageResponse() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let data = Data([1, 2, 3])
        stub(statusCode: 200, mimeType: "image/png", data: data)

        let resource = try await loader.load(
            source: "https://example.com/image.png",
            policy: .remoteHTTPS
        )

        XCTAssertEqual(resource.url.absoluteString, "https://example.com/image.png")
        XCTAssertEqual(resource.data, data)
        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 1)
    }

    func testRemoteHTTPSRejectsHTTPBeforeNetworkIO() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "http://example.com/image.png"))

        await assertLoadingError(.sourceNotAllowed(url)) {
            try await loader.load(source: url.absoluteString, policy: .remoteHTTPS)
        }

        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 0)
    }

    func testRemoteHTTPSRejectsRedirectedHTTPResponse() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/image.png"))
        let redirectedURL = try XCTUnwrap(URL(string: "http://cdn.example.com/image.png"))
        ImageLoaderURLProtocol.state.configure { request in
            XCTAssertEqual(request.url, sourceURL)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: sourceURL,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": redirectedURL.absoluteString]
                )
            )
            return .redirect(
                response: response,
                request: URLRequest(url: redirectedURL)
            )
        }

        await assertLoadingError(.redirectedSourceNotAllowed(redirectedURL)) {
            try await loader.load(
                source: sourceURL.absoluteString,
                policy: .remoteHTTPS
            )
        }
        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 1)
    }

    func testRemoteHTTPSFollowsAllowedHTTPSRedirect() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/image.png"))
        let redirectedURL = try XCTUnwrap(URL(string: "https://cdn.example.com/image.png"))
        let redirectedData = Data([1, 2, 3])

        ImageLoaderURLProtocol.state.configure { request in
            switch request.url {
            case sourceURL:
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: sourceURL,
                        statusCode: 302,
                        httpVersion: nil,
                        headerFields: ["Location": redirectedURL.absoluteString]
                    )
                )
                return .redirect(
                    response: response,
                    request: URLRequest(url: redirectedURL)
                )
            case redirectedURL:
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: redirectedURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "image/png"]
                    )
                )
                return .response(
                    StubbedURLResponse(response: response, chunks: [redirectedData])
                )
            default:
                throw URLError(.badURL)
            }
        }

        let resource = try await loader.load(
            source: sourceURL.absoluteString,
            policy: .remoteHTTPS
        )

        XCTAssertEqual(resource.url, redirectedURL)
        XCTAssertEqual(resource.data, redirectedData)
        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 2)
    }

    func testMultiChunkResponseAssemblesInOrder() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/chunked.png"))
        let chunks = [Data([1, 2]), Data([3]), Data([4, 5, 6])]

        ImageLoaderURLProtocol.state.configure { request in
            XCTAssertEqual(request.url, sourceURL)
            XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
            XCTAssertEqual(request.timeoutInterval, 12)
            return .response(
                StubbedURLResponse(
                    response: try Self.makeResponse(url: sourceURL),
                    chunks: chunks
                )
            )
        }

        let resource = try await loader.load(
            source: sourceURL.absoluteString,
            policy: .remoteHTTPS
        )

        XCTAssertEqual(resource.url, sourceURL)
        XCTAssertEqual(resource.data, Data([1, 2, 3, 4, 5, 6]))
    }

    func testExactMaximumByteBoundarySucceeds() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/exact-cap.png"))
        let policy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["https"],
            maximumResponseBytes: 4
        )

        ImageLoaderURLProtocol.state.configure { _ in
            .response(
                StubbedURLResponse(
                    response: try Self.makeResponse(
                        url: sourceURL,
                        headers: ["Content-Length": "4"]
                    ),
                    chunks: [Data([1, 2]), Data([3, 4])]
                )
            )
        }

        let resource = try await loader.load(
            source: sourceURL.absoluteString,
            policy: policy
        )
        XCTAssertEqual(resource.data, Data([1, 2, 3, 4]))
    }

    func testUnknownContentLengthOverflowReturnsFirstInvalidCount() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/unknown-length.png"))
        let policy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["https"],
            maximumResponseBytes: 3
        )

        ImageLoaderURLProtocol.state.configure { _ in
            .response(
                StubbedURLResponse(
                    response: try Self.makeResponse(url: sourceURL),
                    chunks: [Data([1, 2]), Data([3, 4])]
                )
            )
        }

        await assertLoadingError(.dataTooLarge(4)) {
            try await loader.load(source: sourceURL.absoluteString, policy: policy)
        }
    }

    func testDishonestSmallerContentLengthCannotBypassFinalCap() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/dishonest-length.png"))
        let policy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["https"],
            maximumResponseBytes: 3
        )

        ImageLoaderURLProtocol.state.configure { _ in
            .response(
                StubbedURLResponse(
                    response: try Self.makeResponse(
                        url: sourceURL,
                        headers: ["Content-Length": "2"]
                    ),
                    chunks: [Data([1, 2]), Data([3, 4])]
                )
            )
        }

        await assertLoadingError(.dataTooLarge(4)) {
            try await loader.load(source: sourceURL.absoluteString, policy: policy)
        }
    }

    func testInvalidResponsesCancelBeforeDelayedBodyDelivery() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let policy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["https"],
            maximumResponseBytes: 3
        )
        let cases: [(String, HTTPURLResponse, ImageResourceLoadingError)] = [
            (
                "oversized",
                try Self.makeResponse(
                    url: XCTUnwrap(URL(string: "https://example.com/oversized.png")),
                    headers: ["Content-Length": "4"]
                ),
                .responseTooLarge(4)
            ),
            (
                "status",
                try Self.makeResponse(
                    url: XCTUnwrap(URL(string: "https://example.com/status.png")),
                    statusCode: 404
                ),
                .unacceptableStatusCode(404)
            ),
            (
                "mime",
                try Self.makeResponse(
                    url: XCTUnwrap(URL(string: "https://example.com/mime.png")),
                    mimeType: "text/plain"
                ),
                .unsupportedMIMEType("text/plain")
            ),
        ]

        for (name, response, expectedError) in cases {
            let sourceURL = try XCTUnwrap(response.url)
            let gate = StubbedURLGate()
            ImageLoaderURLProtocol.state.configure { _ in
                .response(
                    StubbedURLResponse(
                        response: response,
                        chunks: [Data([1, 2, 3])],
                        completion: .none,
                        bodyGate: gate,
                        finishesBeforeBody: true
                    )
                )
            }

            await assertLoadingError(expectedError) {
                try await loader.load(source: sourceURL.absoluteString, policy: policy)
            }
            XCTAssertTrue(
                ImageLoaderURLProtocol.state.waitForStop(for: sourceURL),
                "Expected \(name) response to stop loading"
            )
            XCTAssertEqual(
                ImageLoaderURLProtocol.state.deliveredByteCount(for: sourceURL),
                0
            )
            gate.open()
            XCTAssertTrue(
                ImageLoaderURLProtocol.state.waitForWorkerCompletion(for: sourceURL),
                "Expected \(name) body worker to exit"
            )
            XCTAssertEqual(
                ImageLoaderURLProtocol.state.deliveredByteCount(for: sourceURL),
                0
            )
        }
    }

    func testCancellationStopsNeverFinishingResponseAndIgnoresLateCallbacks() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/never-finishes.png"))
        let gate = StubbedURLGate()

        ImageLoaderURLProtocol.state.configure { _ in
            .response(
                StubbedURLResponse(
                    response: try Self.makeResponse(url: sourceURL),
                    chunks: [Data([9, 8, 7])],
                    bodyGate: gate,
                    responseTriggerData: Data([0]),
                    deliversAfterStop: true
                )
            )
        }

        let task = Task {
            try await loader.load(source: sourceURL.absoluteString, policy: .remoteHTTPS)
        }
        XCTAssertTrue(
            ImageLoaderURLProtocol.state.waitForDeliveredByteCount(1, for: sourceURL)
        )

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertTrue(ImageLoaderURLProtocol.state.waitForStop(for: sourceURL))
        gate.open()
        XCTAssertTrue(
            ImageLoaderURLProtocol.state.waitForWorkerCompletion(for: sourceURL)
        )
        XCTAssertEqual(ImageLoaderURLProtocol.state.deliveredByteCount(for: sourceURL), 4)
    }

    func testCancellationBeforeTaskRegistrationThrowsCancellationError() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/pre-cancelled.png"))
        let startGate = StubbedURLGate()
        ImageLoaderURLProtocol.state.configure { _ in
            throw URLError(.cannotLoadFromNetwork)
        }

        let task = Task {
            startGate.wait()
            return try await loader.load(
                source: sourceURL.absoluteString,
                policy: .remoteHTTPS
            )
        }
        XCTAssertTrue(startGate.waitForWaiter())
        task.cancel()
        startGate.open()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 0)
    }

    func testPartialTransportFailurePropagatesOriginalError() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/partial.png"))
        let transportError = URLError(.networkConnectionLost)

        ImageLoaderURLProtocol.state.configure { _ in
            .response(
                StubbedURLResponse(
                    response: try Self.makeResponse(url: sourceURL),
                    chunks: [Data([1, 2]), Data([3])],
                    completion: .failure(transportError)
                )
            )
        }

        do {
            _ = try await loader.load(
                source: sourceURL.absoluteString,
                policy: .remoteHTTPS
            )
            XCTFail("Expected transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, transportError.code)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }
    }

    func testConcurrentLoadsThroughOneLoaderRemainIsolated() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first.png"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second.png"))
        let firstGate = StubbedURLGate()
        let secondGate = StubbedURLGate()

        ImageLoaderURLProtocol.state.configure { request in
            switch request.url {
            case firstURL:
                return .response(
                    StubbedURLResponse(
                        response: try Self.makeResponse(url: firstURL),
                        chunks: [Data([1]), Data([2])],
                        bodyGate: firstGate
                    )
                )
            case secondURL:
                return .response(
                    StubbedURLResponse(
                        response: try Self.makeResponse(url: secondURL),
                        chunks: [Data([8]), Data([9])],
                        bodyGate: secondGate
                    )
                )
            default:
                throw URLError(.badURL)
            }
        }

        async let first = loader.load(
            source: firstURL.absoluteString,
            policy: .remoteHTTPS
        )
        async let second = loader.load(
            source: secondURL.absoluteString,
            policy: .remoteHTTPS
        )

        XCTAssertTrue(ImageLoaderURLProtocol.state.waitForResponse(for: firstURL))
        XCTAssertTrue(ImageLoaderURLProtocol.state.waitForResponse(for: secondURL))
        secondGate.open()
        firstGate.open()

        let (firstResource, secondResource) = try await (first, second)
        XCTAssertEqual(firstResource.url, firstURL)
        XCTAssertEqual(firstResource.data, Data([1, 2]))
        XCTAssertEqual(secondResource.url, secondURL)
        XCTAssertEqual(secondResource.data, Data([8, 9]))
    }

    func testTrustedPolicyLoadsRelativeFileAndHTTP() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let directory = cwd.appendingPathComponent(".build/image-loader-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).bin")
        let fileData = Data([4, 5, 6])
        try fileData.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let relativePath = fileURL.path.replacingOccurrences(of: cwd.path + "/", with: "")

        let fileResource = try await loader.load(source: relativePath, policy: .trusted)
        XCTAssertEqual(fileResource.url, fileURL)
        XCTAssertEqual(fileResource.data, fileData)

        let networkData = Data([7, 8, 9])
        stub(statusCode: 200, mimeType: "image/jpeg", data: networkData)
        let networkResource = try await loader.load(
            source: "http://example.com/image.jpg",
            policy: .trusted
        )
        XCTAssertEqual(networkResource.data, networkData)
        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 1)
    }

    func testInvalidSourceIsRejected() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }

        await assertLoadingError(.invalidSource) {
            try await loader.load(source: "   ", policy: .trusted)
        }
        XCTAssertEqual(ImageLoaderURLProtocol.state.count(), 0)
    }

    func testNonSuccessfulHTTPStatusIsRejected() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        stub(statusCode: 404, mimeType: "image/png", data: Data([1]))

        await assertLoadingError(.unacceptableStatusCode(404)) {
            try await loader.load(
                source: "https://example.com/missing.png",
                policy: .remoteHTTPS
            )
        }
    }

    func testNonImageMIMETypeIsRejected() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        stub(statusCode: 200, mimeType: "text/plain", data: Data([1]))

        do {
            _ = try await loader.load(
                source: "https://example.com/not-image",
                policy: .remoteHTTPS
            )
            XCTFail("Expected non-image MIME type to be rejected")
        } catch let ImageResourceLoadingError.unsupportedMIMEType(mimeType) {
            XCTAssertFalse(mimeType.hasPrefix("image/"))
        } catch {
            XCTFail("Expected unsupportedMIMEType, got \(error)")
        }
    }

    func testExpectedContentLengthLimitIsEnforced() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let policy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["https"],
            maximumResponseBytes: 3
        )
        stub(
            statusCode: 200,
            mimeType: "image/png",
            data: Data([1]),
            headers: ["Content-Length": "4"]
        )

        await assertLoadingError(.responseTooLarge(4)) {
            try await loader.load(
                source: "https://example.com/image.png",
                policy: policy
            )
        }
    }

    func testFinalDataLimitIsEnforced() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        let policy = ImageLoadingPolicy(
            allowedRemoteSchemes: ["https"],
            maximumResponseBytes: 3
        )
        stub(statusCode: 200, mimeType: "image/png", data: Data([1, 2, 3, 4]))

        await assertLoadingError(.dataTooLarge(4)) {
            try await loader.load(
                source: "https://example.com/image.png",
                policy: policy
            )
        }
    }

    func testEmptyDataIsRejected() async throws {
        let (loader, session) = makeLoader()
        defer { session.invalidateAndCancel() }
        stub(statusCode: 200, mimeType: "image/png", data: Data())

        await assertLoadingError(.emptyData) {
            try await loader.load(
                source: "https://example.com/image.png",
                policy: .remoteHTTPS
            )
        }
    }

    private func makeLoader() -> (ImageResourceLoader, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageLoaderURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        return (ImageResourceLoader(urlSession: session), session)
    }

    private func stub(
        statusCode: Int,
        mimeType: String,
        data: Data,
        responseURL: URL? = nil,
        headers: [String: String] = [:]
    ) {
        ImageLoaderURLProtocol.state.configure { request in
            let url = try XCTUnwrap(responseURL ?? request.url)
            var responseHeaders = headers
            responseHeaders["Content-Type"] = mimeType
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: responseHeaders
                )
            )
            return .response(StubbedURLResponse(response: response, chunks: [data]))
        }
    }

    private static func makeResponse(
        url: URL,
        statusCode: Int = 200,
        mimeType: String = "image/png",
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = mimeType
        return try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: responseHeaders
            )
        )
    }

    private func assertLoadingError(
        _ expected: ImageResourceLoadingError,
        operation: () async throws -> LoadedImageResource
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected image loading to fail with \(expected)")
        } catch let error as ImageResourceLoadingError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected ImageResourceLoadingError, got \(error)")
        }
    }
}
