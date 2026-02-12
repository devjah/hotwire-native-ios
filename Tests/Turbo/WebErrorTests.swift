import XCTest
@testable import HotwireNative

class WebErrorTests: XCTestCase {

    // MARK: - isOffline

    func test_isOffline_true_forOfflineURLErrors() {
        let offlineCodes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost]
        for code in offlineCodes {
            let error = WebError(urlError: URLError(code))
            XCTAssertTrue(error.isOffline, "\(code) should be offline")
        }
    }

    func test_isOffline_false_forNonOfflineErrors() {
        XCTAssertFalse(WebError(urlError: URLError(.timedOut)).isOffline)
        XCTAssertFalse(WebError(errorCode: 0, description: nil).isOffline, "Turbo.js errors have no URLError")
    }

    // MARK: - isTimeout

    func test_isTimeout_true_forURLErrorTimedOut() {
        XCTAssertTrue(WebError(urlError: URLError(.timedOut)).isTimeout)
    }

    func test_isTimeout_true_forTurboJSTimeoutCode() {
        // Turbo.js SystemStatusCode.timeoutFailure = -1
        XCTAssertTrue(WebError(errorCode: -1, description: "Timeout").isTimeout)
    }

    func test_isTimeout_false_forOtherErrors() {
        XCTAssertFalse(WebError(urlError: URLError(.notConnectedToInternet)).isTimeout)
    }

    // MARK: - isConnectionError

    func test_isConnectionError_true_forHostErrors() {
        let connectionCodes: [URLError.Code] = [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
        for code in connectionCodes {
            let error = WebError(urlError: URLError(code))
            XCTAssertTrue(error.isConnectionError, "\(code) should be a connection error")
        }
    }

    func test_isConnectionError_false_whenNoURLError() {
        XCTAssertFalse(WebError(errorCode: 0, description: nil).isConnectionError)
    }

    // MARK: - isSslError

    func test_isSslError_true_forSslURLErrors() {
        let sslCodes: [URLError.Code] = [
            .secureConnectionFailed,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .clientCertificateRejected,
        ]
        for code in sslCodes {
            let error = WebError(urlError: URLError(code))
            XCTAssertTrue(error.isSslError, "\(code) should be an SSL error")
        }
    }

    func test_isSslError_false_forNonSslError() {
        XCTAssertFalse(WebError(urlError: URLError(.timedOut)).isSslError)
    }

    // MARK: - Error Descriptions

    func test_errorDescription_forURLErrors() {
        let cases: [(URLError.Code, String)] = [
            (.notConnectedToInternet, "Could not connect to the server."),
            (.cannotFindHost, "Could not connect to the server."),
            (.timedOut, "The request timed out."),
            (.secureConnectionFailed, "A secure connection could not be established."),
            (.httpTooManyRedirects, "Too many redirects occurred."),
            (.badURL, "The URL is invalid."),
        ]

        for (code, expected) in cases {
            let error = WebError(urlError: URLError(code))
            XCTAssertEqual(error.errorDescription, expected, "URLError.\(code) should produce: \(expected)")
        }
    }

    func test_errorDescription_fallsBackToURLErrorDescription_forUnhandledCodes() {
        // URLError codes not specifically handled (e.g., .dataNotAllowed) fall through
        // to urlError.localizedDescription
        let error = WebError(urlError: URLError(.dataNotAllowed))
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotEqual(error.errorDescription, "Could not connect to the server.")
        XCTAssertNotEqual(error.errorDescription, "The request timed out.")
    }

    func test_errorDescription_fallsBackToDescription_whenNoURLError() {
        let error = WebError(errorCode: 0, description: "Network failure")
        XCTAssertEqual(error.errorDescription, "Network failure")
    }

    func test_errorDescription_defaultsToNetworkError_whenDescriptionIsNil() {
        let error = WebError(errorCode: 0, description: nil)
        XCTAssertEqual(error.errorDescription, "Network Error")
    }

    // MARK: - Factory: from URLError

    func test_from_urlError_preservesURLError() {
        let urlError = URLError(.notConnectedToInternet)
        let webError = WebError.from(urlError)
        XCTAssertEqual(webError.urlError, urlError)
        XCTAssertEqual(webError.errorCode, URLError.Code.notConnectedToInternet.rawValue)
    }

    // MARK: - Factory: from generic Error

    func test_from_genericError_extractsURLError() {
        let urlError = URLError(.timedOut)
        let webError = WebError.from(urlError as Error)
        XCTAssertEqual(webError.urlError, urlError)
    }

    func test_from_genericError_wrapsNonURLError() {
        let nsError = NSError(domain: "test", code: 42)
        let webError = WebError.from(nsError as Error)
        XCTAssertNil(webError.urlError)
        XCTAssertEqual(webError.errorCode, 42)
    }

    // MARK: - Factory: from Turbo.js status code

    func test_from_turboStatusCode_zero_isNetworkFailure() {
        let webError = WebError.from(turboStatusCode: 0)
        XCTAssertEqual(webError.errorCode, 0)
        XCTAssertNil(webError.urlError)
    }

    func test_from_turboStatusCode_negative1_isTimeout() {
        let webError = WebError.from(turboStatusCode: -1)
        XCTAssertTrue(webError.isTimeout)
        XCTAssertEqual(webError.errorCode, -1)
    }

    func test_from_turboStatusCode_unknownNegative_defaultsToNetworkError() {
        let webError = WebError.from(turboStatusCode: -99)
        XCTAssertEqual(webError.errorCode, -99)
        XCTAssertNil(webError.urlError)
        XCTAssertNotNil(webError.errorDescription)
    }
}
