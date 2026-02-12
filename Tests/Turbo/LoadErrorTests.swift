import XCTest
@testable import HotwireNative

class LoadErrorTests: XCTestCase {

    func test_errorDescriptions() {
        let cases: [(LoadError, String)] = [
            (.notPresent, "The page could not be loaded due to a configuration error."),
            (.notReady, "The page could not be loaded due to a configuration error."),
            (.contentTypeMismatch, "The server returned an invalid content type."),
            (.invalidResponse, "The server returned an invalid response."),
        ]

        for (error, expected) in cases {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }
}
