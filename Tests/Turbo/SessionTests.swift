import Embassy
@testable import HotwireNative
import WebKit
import XCTest

private let defaultTimeout: TimeInterval = 10000
private let turboTimeout: TimeInterval = 30

class SessionTests: XCTestCase {
    private let sessionDelegate = TestSessionDelegate()
    private var session: Session!
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!

    @MainActor
    override func setUp() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Hotwire Native iOS Test/1.0"

        session = Session(webViewConfiguration: configuration)
        session.delegate = sessionDelegate

        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer.turboServer(eventLoop: eventLoop)
        try server.start()
        DispatchQueue.global().async { self.eventLoop.runForever() }
    }

    override func tearDown() {
        session.webView.configuration.userContentController.removeScriptMessageHandler(forName: "turbo")

        server.stopAndWait()
        eventLoop.stop()
    }

    func test_init_initializesWebViewWithConfiguration() {
        XCTAssertEqual(session.webView.configuration.applicationNameForUserAgent, "Hotwire Native iOS Test/1.0")
    }

    func test_coldBootVisit_makesTheSessionTheVisitableDelegate() {
        let visitable = TestVisitable(url: url("/"))
        XCTAssertNil(visitable.visitableDelegate)

        session.visit(visitable)
        XCTAssertIdentical(visitable.visitableDelegate, session)
    }

    func test_coldBootVisit_callsStartRequest() {
        let visitable = TestVisitable(url: url("/"))
        session.visit(visitable)

        XCTAssertTrue(sessionDelegate.sessionDidStartRequestCalled)
    }

    func test_coldBootVisit_whenVisitSucceeds_callsSessionDidLoadWebViewDelegateMethod() async {
        await visit("/")

        XCTAssertTrue(sessionDelegate.sessionDidLoadWebViewCalled)
        XCTAssertFalse(sessionDelegate.sessionDidFailRequestCalled)
    }

    func test_coldBootVisit_whenVisitSucceeds_callsSessionDidFinishRequestDelegateMethod() async {
        await visit("/")

        XCTAssertTrue(sessionDelegate.sessionDidFinishRequestCalled)
        XCTAssertFalse(sessionDelegate.sessionDidFailRequestCalled)
    }

    func test_coldBootVisit_whenVisitSucceeds_configuresJavaScriptBridge() async throws {
        await visit("/")

        XCTAssertTrue(sessionDelegate.sessionDidLoadWebViewCalled)
        let result = try await session.webView.evaluateJavaScript("Turbo.navigator.adapter == window.turboNative")
        XCTAssertTrue(try XCTUnwrap(result as? Bool))
    }

    func test_coldBootVisit_whenVisitFailsFromHTTPError_callsSessionDidFailRequestDelegateMethod() async {
        await visit("/invalid")

        XCTAssertTrue(sessionDelegate.sessionDidFailRequestCalled)
    }

    func test_coldBootVisit_whenVisitFailsFromHTTPError_providesAnError() async throws {
        await visit("/invalid")

        XCTAssertNotNil(sessionDelegate.failedRequestError)
        let error = try XCTUnwrap(sessionDelegate.failedRequestError)
        XCTAssertEqual(error, .http(.client(.notFound)))
    }

    func test_coldBootVisit_whenVisitFailsFromHTTPError_callsSessionDidFinishRequestDelegateMethod() async {
        await visit("/invalid")

        XCTAssertTrue(sessionDelegate.sessionDidFinishRequestCalled)
    }

    /// A page without Turbo reports both "not ready" and "page load failed",
    /// back to back. The visit fails once, so one error view shows.
    @MainActor
    func test_coldBootVisit_whenVisitFailsFromMissingLibrary_failsOnceWithNotReady() async throws {
        let failed = self.expectation(description: "Wait for the load error.")
        failed.assertForOverFulfill = false
        sessionDelegate.didChange = { failed.fulfill() }

        let visitable = TestVisitable(url: url("/missing-library"))
        session.visit(visitable)
        await fulfillment(of: [failed], timeout: turboTimeout + defaultTimeout)

        let secondFailure = self.expectation(description: "No second load error.")
        secondFailure.isInverted = true
        sessionDelegate.didChange = { secondFailure.fulfill() }
        await fulfillment(of: [secondFailure], timeout: 1)

        XCTAssertEqual(sessionDelegate.allFailedRequestErrors, [.load(.notReady)])
    }

    /// A deploy changes the tracked assets, and Turbo invalidates the page on
    /// the next visit. Going back, that visit is the revealed screen's restore
    /// while the topmost visitable is still the screen being popped: the
    /// reload is the revealed screen's, or its spinner outlives the page.
    @MainActor
    func test_pageInvalidated_whileAnotherVisitableIsVisiting_reloadsTheVisitingOne() async {
        let popped = TestVisitable(url: url("/"))
        let loaded = expectation(description: "Wait for the cold boot.")
        sessionDelegate.didChange = { loaded.fulfill() }
        session.visit(popped)
        await fulfillment(of: [loaded], timeout: defaultTimeout)
        sessionDelegate.didChange = nil
        session.visitableViewDidAppear(popped)
        XCTAssertIdentical(session.topmostVisitable, popped)

        let revealed = TestVisitable(url: url("/"))
        session.visit(revealed, action: .restore)
        XCTAssertIdentical(session.invalidatedVisitable, revealed)

        session.webViewDidInvalidatePage(WebViewBridge(webView: WKWebView()))

        XCTAssertIdentical(session.topmostVisitable, revealed)
        XCTAssertIdentical(session.activeVisitable, revealed)
        XCTAssertTrue(revealed.visitableView.activityIndicatorView.isAnimating)
        XCTAssertFalse(popped.visitableView.activityIndicatorView.isAnimating)
    }

    @MainActor
    func test_pageInvalidated_withNoVisitInFlight_reloadsTheTopmostVisitable() async {
        let visitable = TestVisitable(url: url("/"))
        let loaded = expectation(description: "Wait for the cold boot.")
        sessionDelegate.didChange = { loaded.fulfill() }
        session.visit(visitable)
        await fulfillment(of: [loaded], timeout: defaultTimeout)
        session.visitableViewDidAppear(visitable)

        XCTAssertIdentical(session.invalidatedVisitable, visitable)
    }

    /// Offline, the revealed screen's restore fetch fails inside the pop
    /// animation, while the topmost visitable is still the screen being
    /// popped: the retry's cold boot is the revealed screen's, or its spinner
    /// outlives the page.
    @MainActor
    func test_retryAfterFailedFetch_whileAnotherVisitableIsTopmost_reloadsTheFailedVisitsVisitable() async {
        let popped = TestVisitable(url: url("/"))
        let loaded = expectation(description: "Wait for the cold boot.")
        sessionDelegate.didChange = { loaded.fulfill() }
        session.visit(popped)
        await fulfillment(of: [loaded], timeout: defaultTimeout)
        sessionDelegate.didChange = nil
        session.visitableViewDidAppear(popped)
        XCTAssertIdentical(session.topmostVisitable, popped)

        let revealed = TestVisitable(url: url("/"))
        session.visit(revealed, action: .restore)

        // A JavaScript visit keeps its placeholder identifier until Turbo reports it started.
        session.retryOrFailCurrentVisit(with: .load(.invalidResponse), visitIdentifier: "(pending)")

        XCTAssertIdentical(session.topmostVisitable, revealed)
        XCTAssertIdentical(session.activeVisitable, revealed)
        XCTAssertTrue(revealed.visitableView.activityIndicatorView.isAnimating)
        XCTAssertFalse(popped.visitableView.activityIndicatorView.isAnimating)
    }

    // MARK: - Server

    @MainActor
    private func visit(_ path: String, timeout: TimeInterval = defaultTimeout) async {
        let expectation = self.expectation(description: "Wait for request to load.")
        sessionDelegate.didChange = { expectation.fulfill() }

        let visitable = TestVisitable(url: url(path))
        session.visit(visitable)
        await fulfillment(of: [expectation], timeout: timeout)
    }

    private func url(_ path: String) -> URL {
        let baseURL = URL(string: "http://localhost:8080")!
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(relativePath)
    }
}
