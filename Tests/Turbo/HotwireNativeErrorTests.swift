import XCTest
@testable import HotwireNative

class HotwireNativeErrorTests: XCTestCase {

    // MARK: - Turbo.js SystemStatusCode Mapping
    //
    // These correspond to the three SystemStatusCode values defined in turbo/src/core/drive/visit.js.
    // They are the ONLY non-positive codes Turbo.js sends today.

    func test_turboJSStatusCode_networkFailure_createsWebError() {
        // SystemStatusCode.networkFailure = 0 (fetch errored completely)
        let error = HotwireNativeError(turboJSStatusCode: 0)
        if case .web(let webError) = error {
            XCTAssertEqual(webError.errorCode, 0)
            XCTAssertNil(webError.urlError)
        } else {
            XCTFail("Expected .web error, got \(error)")
        }
    }

    func test_turboJSStatusCode_timeoutFailure_createsTimeoutWebError() {
        // SystemStatusCode.timeoutFailure = -1
        let error = HotwireNativeError(turboJSStatusCode: -1)
        if case .web(let webError) = error {
            XCTAssertTrue(webError.isTimeout)
            XCTAssertEqual(webError.errorCode, -1)
        } else {
            XCTFail("Expected .web error, got \(error)")
        }
    }

    func test_turboJSStatusCode_contentTypeMismatch_createsLoadError() {
        // SystemStatusCode.contentTypeMismatch = -2 (non-HTML response)
        let error = HotwireNativeError(turboJSStatusCode: -2)
        XCTAssertEqual(error, .load(.contentTypeMismatch))
    }

    // MARK: - HTTP Status Codes via visitRequestFailed
    //
    // When the server returns a non-2xx status code, Turbo.js calls
    // adapter.visitRequestFailedWithStatusCode(visit, statusCode).
    // The iOS native adapter routes positive codes through visitRequestFailed →
    // JavaScriptVisit → HotwireNativeError(turboJSStatusCode:).
    // Consumers then pattern-match in NavigatorDelegate.visitableDidFailRequest.

    func test_turboJSStatusCode_httpErrors_mapToExpectedCases() {
        let cases: [(Int, HotwireNativeError)] = [
            (401, .http(.client(.unauthorized))),
            (403, .http(.client(.forbidden))),
            (404, .http(.client(.notFound))),
            (422, .http(.client(.unprocessableEntity))),
            (429, .http(.client(.tooManyRequests))),
            (500, .http(.server(.internalServerError))),
            (502, .http(.server(.badGateway))),
            (503, .http(.server(.serviceUnavailable))),
        ]

        for (statusCode, expected) in cases {
            let error = HotwireNativeError(turboJSStatusCode: statusCode)
            XCTAssertEqual(error, expected, "Status code \(statusCode) should map to \(expected)")
        }
    }

    // MARK: - Unknown 4xx/5xx Codes
    //
    // Valid HTTP error codes the enum doesn't name explicitly.
    // These are real Turbo.js scenarios — the server can return any 4xx/5xx.

    func test_turboJSStatusCode_unknown4xx5xx_mapToOtherCases() {
        let cases: [(Int, HotwireNativeError)] = [
            (410, .http(.client(.other(statusCode: 410)))),   // 410 Gone
            (418, .http(.client(.other(statusCode: 418)))),   // 418 I'm a Teapot
            (451, .http(.client(.other(statusCode: 451)))),   // 451 Unavailable For Legal Reasons
            (506, .http(.server(.other(statusCode: 506)))),   // 506 Variant Also Negotiates
            (520, .http(.server(.other(statusCode: 520)))),   // 520 Cloudflare-specific
        ]

        for (statusCode, expected) in cases {
            let error = HotwireNativeError(turboJSStatusCode: statusCode)
            XCTAssertEqual(error, expected, "Unknown status code \(statusCode) should fall through to .other")
        }
    }

    // MARK: - Unexpected Codes
    //
    // Values that shouldn't realistically arrive through Turbo.js today.
    // Negative codes not in SystemStatusCode, or 1xx/2xx/3xx (browser handles redirects,
    // Turbo.js considers 200-299 successful). These test defensive fallback behavior.

    func test_turboJSStatusCode_unexpectedNegative_createsWebError() {
        // Turbo.js only defines -2, -1, 0 — but future versions could add more
        let error = HotwireNativeError(turboJSStatusCode: -3)
        if case .web(let webError) = error {
            XCTAssertEqual(webError.errorCode, -3)
        } else {
            XCTFail("Expected .web error for unexpected negative code, got \(error)")
        }
    }

    func test_turboJSStatusCode_unexpectedPositive_createsUnknownHttpError() {
        // 1xx and 3xx can't reach Turbo.js through normal flow
        let cases: [(Int, HotwireNativeError)] = [
            (100, .http(.unknownError(statusCode: 100))),
            (301, .http(.unknownError(statusCode: 301))),
        ]

        for (statusCode, expected) in cases {
            let error = HotwireNativeError(turboJSStatusCode: statusCode)
            XCTAssertEqual(error, expected, "Unexpected code \(statusCode) should map to .unknownError")
        }
    }

    // MARK: - Convenience Properties

    func test_statusCode_returnsCode_forHttpError() {
        let error = HotwireNativeError.http(.client(.unauthorized))
        XCTAssertEqual(error.statusCode, 401)
    }

    func test_statusCode_returnsNil_forNonHttpErrors() {
        let cases: [HotwireNativeError] = [
            .web(WebError(errorCode: 0, description: nil)),
            .load(.notPresent),
        ]

        for error in cases {
            XCTAssertNil(error.statusCode, "\(error) should not have a statusCode")
        }
    }

    func test_urlError_returnsURLError_forWebErrorWithURLError() {
        let urlError = URLError(.notConnectedToInternet)
        let error = HotwireNativeError.web(WebError(urlError: urlError))
        XCTAssertEqual(error.urlError, urlError)
    }

    func test_urlError_returnsNil_forNonWebErrors() {
        let cases: [HotwireNativeError] = [
            .http(.client(.notFound)),
            .load(.notPresent),
        ]

        for error in cases {
            XCTAssertNil(error.urlError, "\(error) should not have a urlError")
        }
    }

    // MARK: - Error Descriptions

    func test_errorDescription_delegatesToInnerErrorType() {
        let cases: [(HotwireNativeError, String)] = [
            (.http(.client(.notFound)), "Not Found"),
            (.web(WebError(urlError: URLError(.notConnectedToInternet))), "Could not connect to the server."),
            (.load(.contentTypeMismatch), "The server returned an invalid content type."),
        ]

        for (error, expectedDescription) in cases {
            XCTAssertEqual(error.errorDescription, expectedDescription)
        }
    }
}
