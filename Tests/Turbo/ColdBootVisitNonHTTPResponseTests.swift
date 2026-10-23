import Embassy
@testable import HotwireNative
import WebKit
import XCTest

/// Cold boots that receive a response without an HTTP status, such as one from a
/// `data:` URL or an app-registered URL scheme. Only the page's own response can
/// fail the visit.
final class ColdBootVisitNonHTTPResponseTests: XCTestCase {
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private let schemeHandler = HTMLSchemeHandler()
    private let visitDelegate = TestVisitDelegate()

    override func setUpWithError() throws {
        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer(eventLoop: eventLoop) { _, startResponse, sendBody in
            startResponse("200 OK", [("Content-Type", "text/html")])
            sendBody(Data("<html><body><iframe src=\"\(HTMLSchemeHandler.scheme)://localhost/embed\"></iframe></body></html>".utf8))
            sendBody(Data())
        }
        try server.start()
        let loop = eventLoop!
        DispatchQueue.global().async { loop.runForever() }
    }

    override func tearDown() {
        server.stopAndWait()
        eventLoop.stop()
    }

    func test_nonHTTPResponseForAnIframe_doesNotFailTheVisit() {
        let visit = coldBoot(URL(string: "http://localhost:\(server.listenAddress.port)/")!)

        XCTAssertEqual(schemeHandler.requestedPaths, ["/embed"])
        XCTAssertEqual(visit.state, .started)
        XCTAssertFalse(visitDelegate.didCall("visit(_:requestDidFailWithError:)"))
    }

    func test_nonHTTPResponseForTheMainFrame_failsTheVisit() {
        let visit = coldBoot(URL(string: "\(HTMLSchemeHandler.scheme)://localhost/page")!)

        XCTAssertEqual(visit.state, .failed)
        XCTAssertTrue(visitDelegate.didCall("visit(_:requestDidFailWithError:)"))
    }

    /// Cold boots `url` in a web view that serves the test scheme, and waits for the request to finish.
    private func coldBoot(_ url: URL) -> ColdBootVisit {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: HTMLSchemeHandler.scheme)

        let visit = ColdBootVisit(
            visitable: TestVisitable(url: url),
            options: VisitOptions(),
            bridge: WebViewBridge(webView: WKWebView(frame: .zero, configuration: configuration))
        )
        visit.delegate = visitDelegate
        visit.start()

        let finished = expectation(for: NSPredicate { _, _ in
            self.visitDelegate.didCall("visitRequestDidFinish(_:)")
        }, evaluatedWith: nil)
        wait(for: [finished], timeout: 10)

        return visit
    }
}

/// Answers every request with an HTML page and a plain `URLResponse`, which has no status code.
private final class HTMLSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "hotwire-test"
    private(set) var requestedPaths: [String] = []

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let url = urlSchemeTask.request.url!
        requestedPaths.append(url.path)

        let data = Data("<html><body>Embedded</body></html>".utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/html",
                                             expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
