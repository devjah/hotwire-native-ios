import XCTest
@testable import HotwireNative

final class WebErrorTests: XCTestCase {

    // MARK: - isOffline

    func test_isOffline_true_forNotConnectedToInternet() {
        XCTAssertTrue(WebError(urlError: URLError(.notConnectedToInternet)).isOffline)
    }

    func test_isOffline_true_forNetworkConnectionLost() {
        XCTAssertTrue(WebError(urlError: URLError(.networkConnectionLost)).isOffline)
    }

    func test_isOffline_false_forTimedOut() {
        XCTAssertFalse(WebError(urlError: URLError(.timedOut)).isOffline)
    }

    func test_isOffline_false_whenNoURLError() {
        XCTAssertFalse(WebError(errorCode: 0, description: nil).isOffline)
    }

    // MARK: - isTimeout

    func test_isTimeout_true_forURLErrorTimedOut() {
        XCTAssertTrue(WebError(urlError: URLError(.timedOut)).isTimeout)
    }

    func test_isTimeout_true_forTurboJSTimeoutCode() {
        XCTAssertTrue(WebError(errorCode: -1, description: "Timeout").isTimeout)
    }

    func test_isTimeout_true_forRawTimedOutErrorCode() {
        // URLError.Code.timedOut.rawValue is -1001. The isTimeout check uses errorCode directly,
        // so a WebError constructed without a URLError but with -1001 should still be a timeout.
        XCTAssertTrue(WebError(errorCode: -1001, description: nil).isTimeout)
    }

    func test_isTimeout_false_forNotConnectedToInternet() {
        XCTAssertFalse(WebError(urlError: URLError(.notConnectedToInternet)).isTimeout)
    }

    func test_isTimeout_false_forArbitraryErrorCode() {
        XCTAssertFalse(WebError(errorCode: 0, description: nil).isTimeout)
    }

    // MARK: - isConnectionError

    func test_isConnectionError_true_forCannotFindHost() {
        XCTAssertTrue(WebError(urlError: URLError(.cannotFindHost)).isConnectionError)
    }

    func test_isConnectionError_true_forCannotConnectToHost() {
        XCTAssertTrue(WebError(urlError: URLError(.cannotConnectToHost)).isConnectionError)
    }

    func test_isConnectionError_true_forDnsLookupFailed() {
        XCTAssertTrue(WebError(urlError: URLError(.dnsLookupFailed)).isConnectionError)
    }

    func test_isConnectionError_false_whenNoURLError() {
        XCTAssertFalse(WebError(errorCode: 0, description: nil).isConnectionError)
    }

    func test_isConnectionError_false_forTimedOut() {
        XCTAssertFalse(WebError(urlError: URLError(.timedOut)).isConnectionError)
    }

    // MARK: - isSslError

    func test_isSslError_true_forSecureConnectionFailed() {
        XCTAssertTrue(WebError(urlError: URLError(.secureConnectionFailed)).isSslError)
    }

    func test_isSslError_true_forServerCertificateHasBadDate() {
        XCTAssertTrue(WebError(urlError: URLError(.serverCertificateHasBadDate)).isSslError)
    }

    func test_isSslError_true_forServerCertificateUntrusted() {
        XCTAssertTrue(WebError(urlError: URLError(.serverCertificateUntrusted)).isSslError)
    }

    func test_isSslError_true_forServerCertificateHasUnknownRoot() {
        XCTAssertTrue(WebError(urlError: URLError(.serverCertificateHasUnknownRoot)).isSslError)
    }

    func test_isSslError_true_forServerCertificateNotYetValid() {
        XCTAssertTrue(WebError(urlError: URLError(.serverCertificateNotYetValid)).isSslError)
    }

    func test_isSslError_true_forClientCertificateRejected() {
        XCTAssertTrue(WebError(urlError: URLError(.clientCertificateRejected)).isSslError)
    }

    func test_isSslError_true_forClientCertificateRequired() {
        XCTAssertTrue(WebError(urlError: URLError(.clientCertificateRequired)).isSslError)
    }

    func test_isSslError_false_forTimedOut() {
        XCTAssertFalse(WebError(urlError: URLError(.timedOut)).isSslError)
    }

    func test_isSslError_false_whenNoURLError() {
        XCTAssertFalse(WebError(errorCode: 0, description: nil).isSslError)
    }

    // MARK: - Cross-Classification

    func test_offlineError_isNotTimeout() {
        let error = WebError(urlError: URLError(.notConnectedToInternet))
        XCTAssertTrue(error.isOffline)
        XCTAssertFalse(error.isTimeout)
        XCTAssertFalse(error.isConnectionError)
        XCTAssertFalse(error.isSslError)
    }

    func test_connectionError_isNotOffline() {
        let error = WebError(urlError: URLError(.cannotFindHost))
        XCTAssertTrue(error.isConnectionError)
        XCTAssertFalse(error.isOffline)
        XCTAssertFalse(error.isTimeout)
        XCTAssertFalse(error.isSslError)
    }

    func test_sslError_isNotConnectionError() {
        let error = WebError(urlError: URLError(.secureConnectionFailed))
        XCTAssertTrue(error.isSslError)
        XCTAssertFalse(error.isOffline)
        XCTAssertFalse(error.isTimeout)
        XCTAssertFalse(error.isConnectionError)
    }

    // MARK: - errorDescription

    func test_errorDescription_forNotConnectedToInternet() {
        XCTAssertEqual(
            WebError(urlError: URLError(.notConnectedToInternet)).errorDescription,
            "Could not connect to the server."
        )
    }

    func test_errorDescription_forCannotFindHost() {
        XCTAssertEqual(
            WebError(urlError: URLError(.cannotFindHost)).errorDescription,
            "Could not connect to the server."
        )
    }

    func test_errorDescription_forTimedOut() {
        XCTAssertEqual(
            WebError(urlError: URLError(.timedOut)).errorDescription,
            "The request timed out."
        )
    }

    func test_errorDescription_forSecureConnectionFailed() {
        XCTAssertEqual(
            WebError(urlError: URLError(.secureConnectionFailed)).errorDescription,
            "A secure connection could not be established."
        )
    }

    func test_errorDescription_forHttpTooManyRedirects() {
        XCTAssertEqual(
            WebError(urlError: URLError(.httpTooManyRedirects)).errorDescription,
            "Too many redirects occurred."
        )
    }

    func test_errorDescription_forBadURL() {
        XCTAssertEqual(
            WebError(urlError: URLError(.badURL)).errorDescription,
            "The URL is invalid."
        )
    }

    func test_errorDescription_forUnhandledURLError_fallsBackToSystemDescription() {
        let error = WebError(urlError: URLError(.dataNotAllowed))
        XCTAssertEqual(error.errorDescription, URLError(.dataNotAllowed).localizedDescription)
    }

    func test_errorDescription_usesStoredDescription_whenNoURLError() {
        let error = WebError(errorCode: 0, description: "Network failure")
        XCTAssertEqual(error.errorDescription, "Network failure")
    }

    func test_errorDescription_defaultsToNetworkError_whenDescriptionIsNil() {
        let error = WebError(errorCode: 0, description: nil)
        XCTAssertEqual(error.errorDescription, "Network Error")
    }

    // MARK: - from(URLError)

    func test_from_urlError_preservesURLErrorAndCode() {
        let urlError = URLError(.notConnectedToInternet)
        let webError = WebError.from(urlError)
        XCTAssertEqual(webError.urlError, urlError)
        XCTAssertEqual(webError.errorCode, URLError.Code.notConnectedToInternet.rawValue)
    }

    // MARK: - from(Error)

    func test_from_genericError_extractsURLError() {
        let urlError = URLError(.timedOut)
        let webError = WebError.from(urlError as Error)
        XCTAssertEqual(webError.urlError, urlError)
        XCTAssertEqual(webError.errorCode, URLError.Code.timedOut.rawValue)
    }

    func test_from_genericError_wrapsNonURLError() {
        let nsError = NSError(domain: "test", code: 42)
        let webError = WebError.from(nsError as Error)
        XCTAssertNil(webError.urlError)
        XCTAssertEqual(webError.errorCode, 42)
    }

    // MARK: - Initializers

    func test_init_urlError_setsAllProperties() {
        let urlError = URLError(.notConnectedToInternet)
        let webError = WebError(urlError: urlError)
        XCTAssertEqual(webError.urlError, urlError)
        XCTAssertEqual(webError.errorCode, urlError.code.rawValue)
        XCTAssertEqual(webError.description, urlError.localizedDescription)
    }

    func test_init_errorCode_setsAllProperties() {
        let webError = WebError(errorCode: 42, description: "Custom")
        XCTAssertNil(webError.urlError)
        XCTAssertEqual(webError.errorCode, 42)
        XCTAssertEqual(webError.description, "Custom")
    }

    func test_init_errorCode_nilDescription_defaultsToNetworkError() {
        let webError = WebError(errorCode: 0, description: nil)
        XCTAssertEqual(webError.description, "Network Error")
    }
}
