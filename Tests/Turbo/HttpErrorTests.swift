import XCTest
@testable import HotwireNative

class HttpErrorTests: XCTestCase {

    // MARK: - Status Code Range Boundaries

    func test_from_statusCode_routesToCorrectCategory() {
        let cases: [(Int, String)] = [
            (399, "unknownError"),   // below client range
            (400, "client"),         // start of client range
            (499, "client"),         // end of client range
            (500, "server"),         // start of server range
            (599, "server"),         // end of server range
            (600, "unknownError"),   // above server range
        ]

        for (statusCode, expectedCategory) in cases {
            let error = HttpError.from(statusCode: statusCode)
            switch (error, expectedCategory) {
            case (.client, "client"),
                 (.server, "server"),
                 (.unknownError, "unknownError"):
                break // correct
            default:
                XCTFail("Status code \(statusCode) should be \(expectedCategory), got \(error)")
            }
        }
    }

    // MARK: - ClientError Status Code Round-Trip

    func test_clientError_statusCode_roundTrips() {
        let cases: [(HttpError.ClientError, Int)] = [
            (.badRequest, 400),
            (.unauthorized, 401),
            (.paymentRequired, 402),
            (.forbidden, 403),
            (.notFound, 404),
            (.methodNotAllowed, 405),
            (.notAcceptable, 406),
            (.proxyAuthenticationRequired, 407),
            (.requestTimeout, 408),
            (.conflict, 409),
            (.misdirectedRequest, 421),
            (.unprocessableEntity, 422),
            (.preconditionRequired, 428),
            (.tooManyRequests, 429),
        ]

        for (expectedCase, statusCode) in cases {
            let created = HttpError.ClientError.from(statusCode: statusCode)
            XCTAssertEqual(created, expectedCase, "Status code \(statusCode) should map to \(expectedCase)")
            XCTAssertEqual(created.statusCode, statusCode, "Round-trip failed for \(expectedCase)")
        }
    }

    // MARK: - ServerError Status Code Round-Trip

    func test_serverError_statusCode_roundTrips() {
        let cases: [(HttpError.ServerError, Int)] = [
            (.internalServerError, 500),
            (.notImplemented, 501),
            (.badGateway, 502),
            (.serviceUnavailable, 503),
            (.gatewayTimeout, 504),
            (.httpVersionNotSupported, 505),
        ]

        for (expectedCase, statusCode) in cases {
            let created = HttpError.ServerError.from(statusCode: statusCode)
            XCTAssertEqual(created, expectedCase, "Status code \(statusCode) should map to \(expectedCase)")
            XCTAssertEqual(created.statusCode, statusCode, "Round-trip failed for \(expectedCase)")
        }
    }

    // MARK: - Unmapped Status Codes

    func test_unmappedStatusCodes_fallToOther() {
        let cases: [(Int, HttpError)] = [
            (418, .client(.other(statusCode: 418))),   // I'm a Teapot
            (451, .client(.other(statusCode: 451))),   // Unavailable For Legal Reasons
            (599, .server(.other(statusCode: 599))),
        ]

        for (statusCode, expected) in cases {
            let error = HttpError.from(statusCode: statusCode)
            XCTAssertEqual(error, expected, "Unmapped code \(statusCode) should fall to .other")
            XCTAssertEqual(error.statusCode, statusCode, "Status code should round-trip for .other")
        }
    }

    // MARK: - Error Descriptions

    func test_clientError_descriptions() {
        let cases: [(HttpError.ClientError, String)] = [
            (.unauthorized, "Unauthorized"),
            (.notFound, "Not Found"),
            (.tooManyRequests, "Too Many Requests"),
            (.other(statusCode: 418), "Client Error (418)"),
        ]

        for (error, expected) in cases {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    func test_serverError_descriptions() {
        let cases: [(HttpError.ServerError, String)] = [
            (.internalServerError, "Internal Server Error"),
            (.serviceUnavailable, "Service Unavailable"),
            (.other(statusCode: 599), "Server Error (599)"),
        ]

        for (error, expected) in cases {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    func test_unknownError_description_includesStatusCode() {
        XCTAssertEqual(HttpError.unknownError(statusCode: 600).errorDescription, "HTTP Error (600)")
    }
}
