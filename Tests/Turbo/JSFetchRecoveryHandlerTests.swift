@testable import HotwireNative
import XCTest

// On the main actor because `resolve(location:)` reads `Hotwire.config` for its
// default timeout. The first read builds a `WKProcessPool`, which initializes
// WebKit, and WebKit traps when that happens off the main thread. Run alone,
// these async tests would otherwise do it from the cooperative thread pool.
@MainActor
final class JSFetchRecoveryHandlerTests: XCTestCase {
    private let handler = JSFetchRecoveryHandler()
    private let testURL = URL(string: "https://example.com/page")!

    override func setUp() {
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.removeAllStubs()
    }

    // MARK: - No redirect

    func test_resolve_noRedirect_whenResponseURLMatchesRequestURL() async throws {
        StubURLProtocol.stub(testURL, statusCode: 200)

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .noRedirect)
    }

    // MARK: - Same-origin redirect

    func test_resolve_sameOriginRedirect_whenResponseURLDiffersButSameHost() async throws {
        let redirectURL = URL(string: "https://example.com/other")!

        StubURLProtocol.stub(testURL, statusCode: 301, headers: ["Location": redirectURL.absoluteString])
        StubURLProtocol.stub(redirectURL, statusCode: 200)

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .sameOriginRedirect(redirectURL))
    }

    // MARK: - Cross-origin redirect

    func test_resolve_crossOriginRedirect_whenResponseURLHasDifferentHost() async throws {
        let redirectURL = URL(string: "https://other.com/page")!

        StubURLProtocol.stub(testURL, statusCode: 301, headers: ["Location": redirectURL.absoluteString])
        StubURLProtocol.stub(redirectURL, statusCode: 200)

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .crossOriginRedirect(redirectURL))
    }

    // MARK: - Request failure

    func test_resolve_throwsRequestFailed_whenNetworkErrorOccurs() async {
        StubURLProtocol.stub(testURL, error: URLError(.notConnectedToInternet))

        do {
            _ = try await handler.resolve(location: testURL)
            XCTFail("Expected requestFailed error")
        } catch let error as JSFetchRecoveryError {
            guard case .requestFailed = error else {
                return XCTFail("Expected .requestFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Non-2xx responses (after 1b fix: any HTTP response is valid)

    func test_resolve_noRedirect_whenNon2xxResponseWithSameURL() async throws {
        // A 401 or 500 response still means the server is reachable.
        // After removing the status code validation, this should return .noRedirect.
        StubURLProtocol.stub(testURL, statusCode: 401)

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .noRedirect)
    }

    func test_resolve_noRedirect_when500ResponseWithSameURL() async throws {
        StubURLProtocol.stub(testURL, statusCode: 500)

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .noRedirect)
    }

    // MARK: - Non-2xx with redirect

    func test_resolve_detectsRedirect_evenWhenFinalResponseIsNon2xx() async throws {
        let redirectURL = URL(string: "https://other.com/login")!

        StubURLProtocol.stub(testURL, statusCode: 301, headers: ["Location": redirectURL.absoluteString])
        StubURLProtocol.stub(redirectURL, statusCode: 401)

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .crossOriginRedirect(redirectURL))
    }
}

// MARK: - Stubbed responses

/// Answers requests to stubbed URLs with canned responses, the way a server would.
///
/// OHHTTPStubs can't stand in here. After it reports a redirect, it goes on to
/// deliver the 3xx response and finish loading, while URLSession is already
/// following the redirect with a new request. That leaves the task with two
/// endings, and `URLSession.data(for:)` traps on the second one, killing the
/// test runner. This protocol only reports the redirect, then URLSession stops
/// it and loads the new location through a fresh instance.
private final class StubURLProtocol: URLProtocol {
    private enum Stub {
        case response(statusCode: Int, headers: [String: String])
        case failure(Error)
    }

    // URLSession asks `canInit(with:)` from its own threads.
    private static let lock = NSLock()
    private static var stubs: [URL: Stub] = [:]

    static func stub(_ url: URL, statusCode: Int, headers: [String: String] = [:]) {
        setStub(.response(statusCode: statusCode, headers: headers), for: url)
    }

    static func stub(_ url: URL, error: Error) {
        setStub(.failure(error), for: url)
    }

    static func removeAllStubs() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
    }

    private static func setStub(_ stub: Stub, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stubs[url] = stub
    }

    private static func stub(for request: URLRequest) -> Stub? {
        guard let url = request.url else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return stubs[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        stub(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client = client else { return }
        guard let url = request.url, let stub = Self.stub(for: request) else {
            client.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        switch stub {
        case .failure(let error):
            client.urlProtocol(self, didFailWithError: error)

        case .response(let statusCode, let headers):
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!

            if (300..<400).contains(statusCode),
               let location = headers["Location"],
               let redirectURL = URL(string: location, relativeTo: url)?.absoluteURL {
                var redirectRequest = request
                redirectRequest.url = redirectURL
                client.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: response)
                return
            }

            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Equatable for test assertions

extension JSFetchRecoveryHandler.Result: Equatable {
    public static func == (lhs: JSFetchRecoveryHandler.Result, rhs: JSFetchRecoveryHandler.Result) -> Bool {
        switch (lhs, rhs) {
        case (.noRedirect, .noRedirect):
            return true
        case (.sameOriginRedirect(let lhsURL), .sameOriginRedirect(let rhsURL)):
            return lhsURL == rhsURL
        case (.crossOriginRedirect(let lhsURL), .crossOriginRedirect(let rhsURL)):
            return lhsURL == rhsURL
        default:
            return false
        }
    }
}
