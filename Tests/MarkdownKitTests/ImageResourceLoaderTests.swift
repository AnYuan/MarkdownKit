import Foundation
import XCTest
@testable import MarkdownKit

private struct StubbedURLResponse {
    let response: URLResponse
    let data: Data
}

private enum StubbedURLAction {
    case response(StubbedURLResponse)
    case redirect(response: HTTPURLResponse, request: URLRequest)
}

private final class ImageLoaderURLProtocolState: @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> StubbedURLAction

    private let lock = NSLock()
    private var handler: Handler?
    private var requestCount = 0

    func configure(handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        requestCount = 0
        lock.unlock()
    }

    func reset() {
        lock.lock()
        handler = nil
        requestCount = 0
        lock.unlock()
    }

    func action(for request: URLRequest) throws -> StubbedURLAction {
        let handler: Handler?
        lock.lock()
        requestCount += 1
        handler = self.handler
        lock.unlock()

        guard let handler else {
            throw URLError(.resourceUnavailable)
        }
        return try handler(request)
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }
}

private final class ImageLoaderURLProtocol: URLProtocol {
    static let state = ImageLoaderURLProtocolState()

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
                client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: stub.data)
                client?.urlProtocolDidFinishLoading(self)
            case let .redirect(response, request):
                client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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
                    StubbedURLResponse(response: response, data: redirectedData)
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
            return .response(StubbedURLResponse(response: response, data: data))
        }
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
