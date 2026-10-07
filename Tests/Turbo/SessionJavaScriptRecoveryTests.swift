import Embassy
@testable import HotwireNative
import UIKit
import WebKit
import XCTest

final class SessionJavaScriptRecoveryTests: XCTestCase {
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private var session: Session!
    private var delegate: JavaScriptRecoveryDelegate!
    private var window: UIWindow!

    override func setUpWithError() throws {
        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer.turboServer(eventLoop: eventLoop, port: 0)
        try server.start()
        let loop = eventLoop!
        DispatchQueue.global().async { loop.runForever() }
        session = Session(webView: WKWebView())
        delegate = JavaScriptRecoveryDelegate()
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
    func test_navigationException_recoversWithColdBootOfRequestedPage() async throws {
        try await assertRecovery(throwing: "new Error('navigation adapter failed')")
    }

    @MainActor
    func test_thrownStringWithoutStack_recoversWithColdBootOfRequestedPage() async throws {
        try await assertRecovery(throwing: "'navigation adapter failed'")
    }

    @MainActor
    func test_snapshotException_doesNotColdBootHealthyNavigation() async throws {
        _ = await loadInitialPage()
        // The bundled Turbo beta predates this optional same-page helper.
        try await session.webView.evaluateJavaScript("""
            Turbo.navigator.locationWithActionIsSamePage = () => false;
            window.turboNative.cacheSnapshot = () => { throw new Error('snapshot failed') };
            true
            """)
        let page = RenderingVisitable(url: url("/?page=2"))
        let rendered = expectation(description: "The JavaScript visit rendered")
        page.didRender = { rendered.fulfill() }

        display(page)
        await fulfillment(of: [rendered], timeout: 15)

        XCTAssertEqual(delegate.loadCount, 1)
        XCTAssertEqual(session.webView.url, page.initialVisitableURL)
        XCTAssertFalse(page.visitableView.isShowingScreenshot)
    }

    @MainActor
    private func assertRecovery(throwing expression: String) async throws {
        _ = await loadInitialPage()
        try await session.webView.evaluateJavaScript("window.turboNative.visitLocationWithOptionsAndRestorationIdentifier = () => { throw \(expression) }; true")
        let page = RenderingVisitable(url: url("/?page=2"))
        let recovered = expectation(description: "The failed JavaScript visit recovered with a cold boot")
        delegate.didLoad = { recovered.fulfill() }

        display(page)
        await fulfillment(of: [recovered], timeout: 15)

        XCTAssertEqual(delegate.loadCount, 2)
        XCTAssertEqual(session.webView.url, page.initialVisitableURL)
        XCTAssertTrue(page.rendered)
        XCTAssertFalse(page.visitableView.isShowingScreenshot)
        XCTAssertFalse(page.visitableView.activityIndicatorView.isAnimating)
        XCTAssertEqual(delegate.failureCount, 0)
    }

    @MainActor
    private func loadInitialPage() async -> RenderingVisitable {
        let loaded = expectation(description: "The initial Turbo page loaded")
        delegate.didLoad = { loaded.fulfill() }
        let page = RenderingVisitable(url: url("/"))
        display(page)
        await fulfillment(of: [loaded], timeout: 15)
        delegate.didLoad = nil
        return page
    }

    @MainActor
    private func display(_ page: RenderingVisitable) {
        session.visit(page)
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
    private(set) var rendered = false

    override func visitableDidRender() {
        super.visitableDidRender()
        rendered = true
        didRender?()
    }
}

private final class JavaScriptRecoveryDelegate: SessionDelegate {
    var didLoad: (() -> Void)?
    private(set) var loadCount = 0
    private(set) var failureCount = 0

    func session(_ session: Session, didProposeVisit proposal: VisitProposal) {}
    func session(_ session: Session, didProposeVisitToCrossOriginRedirect location: URL) {}
    func sessionWebViewProcessDidTerminate(_ session: Session) {}

    func sessionDidLoadWebView(_ session: Session) {
        loadCount += 1
        session.webView.navigationDelegate = session
        didLoad?()
    }

    func session(_ session: Session, didFailRequestForVisitable visitable: Visitable, error: HotwireNativeError) {
        failureCount += 1
    }

    func session(_ session: Session, decidePolicyFor navigationAction: WKNavigationAction) -> WebViewPolicyManager.Decision {
        .allow
    }
}
