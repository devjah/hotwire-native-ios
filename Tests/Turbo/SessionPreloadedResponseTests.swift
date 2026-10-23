import Embassy
@testable import HotwireNative
import UIKit
import WebKit
import XCTest

/// A visit can arrive with its response already loaded: the replace visit
/// Turbo proposes after following a redirect, or the visit after a GET form.
/// When the snapshot cache holds an older copy of the same page, the response
/// must still be what ends up on screen.
final class SessionPreloadedResponseTests: XCTestCase {
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private var session: Session!
    private var delegate: PreloadedResponseDelegate!
    private var window: UIWindow!

    override func setUpWithError() throws {
        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer.turboServer(eventLoop: eventLoop, port: 0)
        try server.start()
        let loop = eventLoop!
        DispatchQueue.global().async { loop.runForever() }
        session = Session(webView: WKWebView())
        delegate = PreloadedResponseDelegate()
        session.delegate = delegate
        window = UIWindow(frame: UIScreen.main.bounds)
    }

    override func tearDown() {
        session.webView.stopLoading()
        window.isHidden = true
        window.rootViewController = nil
        window = nil
        session = nil
        server.stopAndWait()
        eventLoop.stop()
    }

    @MainActor
    func test_visitWithResponse_rendersResponseOverCachedSnapshot() async throws {
        await loadInitialPage()
        // The bundled Turbo beta predates this optional same-page helper.
        try await session.webView.evaluateJavaScript("""
            Turbo.navigator.locationWithActionIsSamePage = () => false;
            document.body.insertAdjacentHTML("beforeend", "<p id='stale'></p>");
            true
            """)
        // Leaving "/" caches its snapshot, marker included.
        await render(RenderingVisitable(url: url("/?page=2")))

        let response = VisitResponse(
            statusCode: 200,
            redirected: true,
            responseHTML: "<html><head><title>Fresh</title></head><body><p id='fresh'></p></body></html>"
        )
        await render(RenderingVisitable(url: url("/")), options: VisitOptions(action: .replace, response: response))

        let page = try await session.webView.evaluateJavaScript("""
            (document.getElementById("fresh") ? "fresh" : "") + (document.getElementById("stale") ? "stale" : "")
            """) as? String
        XCTAssertEqual(page, "fresh")
    }

    @MainActor
    private func loadInitialPage() async {
        let loaded = expectation(description: "The initial Turbo page loaded")
        delegate.didLoad = { loaded.fulfill() }
        display(RenderingVisitable(url: url("/")))
        await fulfillment(of: [loaded], timeout: 15)
        delegate.didLoad = nil
    }

    @MainActor
    private func render(_ page: RenderingVisitable, options: VisitOptions? = nil) async {
        let rendered = expectation(description: "The JavaScript visit rendered")
        page.didRender = { rendered.fulfill() }
        display(page, options: options)
        await fulfillment(of: [rendered], timeout: 15)
        page.didRender = nil
    }

    @MainActor
    private func display(_ page: RenderingVisitable, options: VisitOptions? = nil) {
        session.visit(page, options: options)
        window.rootViewController = page
        window.makeKeyAndVisible()
        page.loadViewIfNeeded()
        session.visitableViewDidAppear(page)
    }

    private func url(_ path: String) -> URL {
        URL(string: "http://localhost:\(server.listenAddress.port)\(path)")!
    }
}

private final class RenderingVisitable: VisitableViewController {
    var didRender: (() -> Void)?

    override func visitableDidRender() {
        super.visitableDidRender()
        didRender?()
    }
}

private final class PreloadedResponseDelegate: SessionDelegate {
    var didLoad: (() -> Void)?

    func session(_ session: Session, didProposeVisit proposal: VisitProposal) {}
    func session(_ session: Session, didProposeVisitToCrossOriginRedirect location: URL) {}
    func sessionWebViewProcessDidTerminate(_ session: Session) {}

    func sessionDidLoadWebView(_ session: Session) {
        session.webView.navigationDelegate = session
        didLoad?()
    }

    func session(_ session: Session, didFailRequestForVisitable visitable: Visitable, error: HotwireNativeError) {}

    func session(_ session: Session, decidePolicyFor navigationAction: WKNavigationAction) -> WebViewPolicyManager.Decision {
        .allow
    }
}
