@testable import HotwireNative
import WebKit
import XCTest

class ScriptMessageTests: XCTestCase {
    func test_parse_withValidData_returnsMessage() throws {
        let data = ["identifier": "123", "restorationIdentifier": "abc", "options": ["action": "advance"], "location": "http://turbo.test"] as [String: Any]
        let script = FakeScriptMessage(body: ["name": "pageLoaded", "data": data] as [String: Any])

        let message = try XCTUnwrap(ScriptMessage(message: script))
        XCTAssertEqual(message.name, .pageLoaded)
        XCTAssertEqual(message.identifier, "123")
        XCTAssertEqual(message.restorationIdentifier, "abc")

        let options = try XCTUnwrap(message.options)
        XCTAssertEqual(options.action, .advance)
        XCTAssertEqual(message.location, URL(string: "http://turbo.test")!)
    }

    func test_parse_rejectsMissingRequiredFields() {
        let names: [ScriptMessage.Name] = [
            .pageLoaded, .visitProposed, .visitStarted, .visitRequestStarted,
            .visitRequestCompleted, .visitRequestFailed, .visitRequestFinished,
            .visitRendered, .visitCompleted, .formSubmissionStarted, .formSubmissionFinished,
            .visitRequestFailedWithNonHttpStatusCode
        ]
        XCTAssertEqual(names.count, 12)
        for name in names {
            let script = FakeScriptMessage(body: ["name": name.rawValue, "data": [:]])
            XCTAssertNil(ScriptMessage(message: script), "Accepted incomplete \(name)")
        }
    }

    func test_parse_rejectsIncorrectFieldTypes() {
        let cases: [(ScriptMessage.Name, [String: Any])] = [
            (.pageLoaded, ["restorationIdentifier": 123]),
            (.visitProposed, ["location": "https://example.com", "options": "advance"]),
            (.visitProposed, ["location": 123, "options": [:]]),
            (.visitStarted, ["identifier": "123", "hasCachedSnapshot": "true", "isPageRefresh": false]),
            (.visitStarted, ["identifier": "123", "hasCachedSnapshot": true, "isPageRefresh": "false"]),
            (.visitRequestFailed, ["identifier": "123", "statusCode": "500"]),
            (.visitCompleted, ["identifier": "123", "restorationIdentifier": false])
        ]
        XCTAssertEqual(cases.count, 7)
        for (name, data) in cases {
            let script = FakeScriptMessage(body: ["name": name.rawValue, "data": data])
            XCTAssertNil(ScriptMessage(message: script), "Accepted malformed \(name)")
        }
    }

    func test_parse_acceptsRequiredFieldsForEveryEvent() {
        let cases: [(ScriptMessage.Name, [String: Any])] = [
            (.pageLoaded, ["restorationIdentifier": "abc"]),
            (.visitProposed, ["location": "https://example.com", "options": ["action": "advance"]]),
            (.visitStarted, ["identifier": "123", "hasCachedSnapshot": false, "isPageRefresh": false]),
            (.visitRequestStarted, ["identifier": "123"]),
            (.visitRequestCompleted, ["identifier": "123"]),
            (.visitRequestFailed, ["identifier": "123", "statusCode": 500]),
            (.visitRequestFinished, ["identifier": "123"]),
            (.visitRendered, ["identifier": "123"]),
            (.visitCompleted, ["identifier": "123", "restorationIdentifier": "abc"]),
            (.formSubmissionStarted, ["location": "https://example.com"]),
            (.formSubmissionFinished, ["location": "https://example.com"]),
            (.visitRequestFailedWithNonHttpStatusCode,
             ["location": "https://example.com", "identifier": "123", "statusCode": 0]),
            (.pageInvalidated, [:]), (.pageLoadFailed, [:]), (.turboIsReady, ["isReady": true]),
            (.errorRaised, [:]), (.log, [:]),
            (.visitProposalScrollingToAnchor, [:]), (.visitProposalRefreshingPage, [:])
        ]
        XCTAssertEqual(cases.count, 19)
        for (name, data) in cases {
            let script = FakeScriptMessage(body: ["name": name.rawValue, "data": data])
            XCTAssertNotNil(ScriptMessage(message: script), "Rejected valid \(name)")
        }
    }

    func test_parse_withInvalidBody_returnsNil() {
        let script = FakeScriptMessage(body: "foo")

        let message = ScriptMessage(message: script)
        XCTAssertNil(message)
    }

    func test_parse_withInvalidName_returnsNil() {
        let script = FakeScriptMessage(body: ["name": "foobar"])

        let message = ScriptMessage(message: script)
        XCTAssertNil(message)
    }

    func test_parse_withMissingData_returnsNil() {
        let script = FakeScriptMessage(body: ["name": "pageLoaded"])

        let message = ScriptMessage(message: script)
        XCTAssertNil(message)
    }

    func test_parse_turboIsReady_withFalse_returnsMessage() throws {
        let data: [String: Any] = ["isReady": false, "timestamp": 0]
        let script = FakeScriptMessage(body: ["name": "turboIsReady", "data": data] as [String: Any])

        let message = try XCTUnwrap(ScriptMessage(message: script))
        XCTAssertEqual(message.name, .turboIsReady)
        XCTAssertEqual(message.data["isReady"] as? Bool, false)
    }

    func test_parse_turboIsReady_withTrue_returnsMessage() throws {
        let data: [String: Any] = ["isReady": true, "timestamp": 0]
        let script = FakeScriptMessage(body: ["name": "turboIsReady", "data": data] as [String: Any])

        let message = try XCTUnwrap(ScriptMessage(message: script))
        XCTAssertEqual(message.name, .turboIsReady)
        XCTAssertEqual(message.data["isReady"] as? Bool, true)
    }
}

// Can't instantiate a WKScriptMessage directly
private class FakeScriptMessage: WKScriptMessage {
    override var body: Any {
        return actualBody
    }

    var actualBody: Any

    init(body: Any) {
        self.actualBody = body
    }
}
