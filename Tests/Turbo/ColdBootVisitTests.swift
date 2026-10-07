import Embassy
@testable import HotwireNative
import WebKit
import XCTest

class ColdBootVisitTests: XCTestCase {
    private let webView = WKWebView()
    private let visitDelegate = TestVisitDelegate()
    private var visit: ColdBootVisit!
    private var visitable: TestVisitable!
    let url = URL(string: "http://localhost/")!

    override func setUp() {

        let bridge = WebViewBridge(webView: webView)
        visitable = TestVisitable(url: url)
        visitable.currentVisitableURL = URL(string: "http://localhost/new")!

        visit = ColdBootVisit(visitable: visitable, options: VisitOptions(), bridge: bridge)
        visit.delegate = visitDelegate
    }

    @MainActor
    func test_subframeHTTPError_doesNotFailThePageVisit() async throws {
        try await assertResponsePolicy(mainFrame: false, http: true, policy: .allow, state: .started)
    }

    @MainActor
    func test_subframeNonHTTPResponse_doesNotFailThePageVisit() async throws {
        try await assertResponsePolicy(mainFrame: false, http: false, policy: .allow, state: .started)
    }

    @MainActor
    func test_mainFrameHTTPError_stillFailsThePageVisit() async throws {
        try await assertResponsePolicy(mainFrame: true, http: true, policy: .cancel, state: .failed)
    }

    @MainActor
    func test_mainFrameNonHTTPResponse_stillFailsThePageVisit() async throws {
        try await assertResponsePolicy(mainFrame: true, http: false, policy: .cancel, state: .failed)
    }

    @MainActor
    private func assertResponsePolicy(mainFrame: Bool, http: Bool,
                                      policy: WKNavigationResponsePolicy, state: VisitState) async throws {
        let eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        let frameURL = http ? "/frame" : "response-test://localhost/frame"
        let server = DefaultHTTPServer(eventLoop: eventLoop, interface: "127.0.0.1") { environ, startResponse, sendBody in
            let isError = mainFrame || environ["PATH_INFO"] as? String == "/frame"
            startResponse(isError ? "404 Not Found" : "200 OK", [("Content-Type", "text/html")])
            let body = isError ? "<html>missing</html>" : "<html><iframe src='\(frameURL)'></iframe></html>"
            sendBody(Data(body.utf8))
            sendBody(Data())
        }
        try server.start()
        DispatchQueue.global().async { eventLoop.runForever() }
        defer {
            server.stopAndWait()
            eventLoop.stop()
        }

        let handler = ResponseSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "response-test")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let bridge = WebViewBridge(webView: webView)
        let location = mainFrame && !http ? URL(string: "response-test://localhost/main")!
            : URL(string: "http://127.0.0.1:\(server.listenAddress.port)/main")!
        let visit = ColdBootVisit(visitable: TestVisitable(url: location),
                                  options: VisitOptions(), bridge: bridge)
        let responseReceived = expectation(description: "WebKit delivered the target frame response")
        let observer = ResponsePolicyObserver(visit: visit, mainFrame: mainFrame) { actualPolicy in
            XCTAssertEqual(actualPolicy, policy)
            XCTAssertEqual(visit.state, state)
            responseReceived.fulfill()
        }

        visit.start()
        webView.navigationDelegate = observer
        await fulfillment(of: [responseReceived], timeout: 30)
        XCTAssertEqual(observer.responseCount, 1)
        webView.stopLoading()
    }

    func test_start_transitionsToStartState() {
        XCTAssertEqual(visit.state, .initialized)
        visit.start()
        XCTAssertEqual(visit.state, .started)
    }

    func test_start_notifiesTheDelegateTheVisitWillStart() {
        visit.start()
        XCTAssertTrue(visitDelegate.didCall("visitWillStart(_:)"))
    }

    func test_start_kicksOffTheWebViewLoad() {
        visit.start()
        XCTAssertNotNil(visit.navigation)
    }

    func test_visit_becomesTheNavigationDelegate() {
        visit.start()
        XCTAssertIdentical(webView.navigationDelegate, visit)
    }

    func test_visit_notifiesTheDelegateTheVisitDidStart() {
        visit.start()
        XCTAssertTrue(visitDelegate.didCall("visitDidStart(_:)"))
    }

    func test_visit_ignoresTheCallIfAlreadyStarted() {
        visit.start()
        XCTAssertTrue(visitDelegate.methodsCalled.contains("visitDidStart(_:)"))

        visitDelegate.methodsCalled.remove("visitDidStart(_:)")
        visit.start()
        XCTAssertFalse(visitDelegate.didCall("visitDidStart(_:)"))
    }

    func test_visit_takesTheCurrentVisitableURL() {
        visit.start()
        XCTAssertTrue(visitDelegate.visitDidStartWasCalled)
        XCTAssertEqual(URL(string: "http://localhost/new")!, visitDelegate.visitDidStartVisit?.location)
    }
}

// Obtain real WKNavigationResponse instances: the framework owns their internal
// storage, so constructing a subclass with NSObject.init is not safe.
private final class ResponseSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let data = Data("<html>embedded content</html>".utf8)
        let response = URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html",
                                   expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class ResponsePolicyObserver: NSObject, WKNavigationDelegate {
    private let visit: ColdBootVisit
    private let mainFrame: Bool
    private let onResponse: (WKNavigationResponsePolicy) -> Void
    private(set) var responseCount = 0

    init(visit: ColdBootVisit, mainFrame: Bool, onResponse: @escaping (WKNavigationResponsePolicy) -> Void) {
        self.visit = visit
        self.mainFrame = mainFrame
        self.onResponse = onResponse
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        var decision: WKNavigationResponsePolicy?
        visit.webView(webView, decidePolicyFor: navigationResponse) { policy in
            decision = policy
            decisionHandler(policy)
        }
        if navigationResponse.isForMainFrame == mainFrame, let decision {
            responseCount += 1
            onResponse(decision)
        }
    }
}
