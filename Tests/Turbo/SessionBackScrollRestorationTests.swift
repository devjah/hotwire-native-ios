import Embassy
@testable import HotwireNative
import UIKit
import WebKit
import XCTest

/// Going back, the session starts the revealed screen's restore visit while the
/// web view still shows the page being popped. With the keyboard up, moving the
/// web view off the popped screen closes the keyboard, and UIKit clamps the
/// shared scroll view to the popped page's range. WebKit hands that scroll to the
/// page a frame later, after the restore visit has made the revealed page Turbo's
/// current history entry, so Turbo used to record the popped page's offset as the
/// revealed page's position and restore it.
///
/// The pages here are plain view controllers that no container owns, so UIKit
/// sends them no appearance callbacks: each test drives the session through the
/// callbacks a navigation controller sends, in its order.
final class SessionBackScrollRestorationTests: XCTestCase {
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private var session: Session!
    private var delegate: BackScrollSessionDelegate!
    private var window: UIWindow!
    private var container: UIViewController!

    override func setUpWithError() throws {
        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer.turboServer(eventLoop: eventLoop, port: 0)
        try server.start()
        let loop = eventLoop!
        DispatchQueue.global().async { loop.runForever() }
        delegate = BackScrollSessionDelegate()
        session = makeSession()
        container = UIViewController()
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = container
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        session.webView.stopLoading()
        window.isHidden = true
        window.rootViewController = nil
        window = nil
        container = nil
        session = nil
        server.stopAndWait()
        eventLoop.stop()
    }

    @MainActor
    func test_back_whenTheKeyboardClosingScrollsThePoppedPage_restoresTheRevealedPagesPosition() async throws {
        let list = await coldBoot("/scroll?page=list")
        try await scroll(to: 600)
        let thread = await push("/scroll?page=thread", over: list)

        await back(from: thread, to: list, whileRevealing: closeKeyboard)

        let position = try await scrollPosition()
        XCTAssertEqual(position, 600)
        XCTAssertFalse(list.visitableView.isShowingScreenshot)
    }

    /// A back swipe abandoned halfway: the list's restore visit renders under its
    /// screenshot while the finger is down, then the thread comes back.
    @MainActor
    func test_cancelledBackSwipe_leavesEachPageAtItsOwnPosition() async throws {
        let list = await coldBoot("/scroll?page=list")
        try await scroll(to: 600)
        let thread = await push("/scroll?page=thread", over: list)
        try await scroll(to: 300)

        let listRendered = expectation(description: "The list rendered under the swipe")
        list.didRender = { listRendered.fulfill() }
        list.didActivateWebView = closeKeyboard
        session.visitableViewWillDisappear(thread)
        show(list)
        session.visitableViewWillAppear(list)
        list.didActivateWebView = nil
        await fulfillment(of: [listRendered], timeout: timeout)
        list.didRender = nil

        let threadRendered = expectation(description: "The thread rendered again")
        thread.didRender = { threadRendered.fulfill() }
        session.visitableViewWillDisappear(list)
        show(thread)
        session.visitableViewWillAppear(thread)
        session.visitableViewDidDisappear(list)
        session.visitableViewDidAppear(thread)
        await fulfillment(of: [threadRendered], timeout: timeout)
        thread.didRender = nil

        let threadPosition = try await scrollPosition()
        XCTAssertEqual(threadPosition, 300)
        XCTAssertFalse(thread.visitableView.isShowingScreenshot)
        XCTAssertFalse(thread.visitableView.activityIndicatorView.isAnimating)

        await back(from: thread, to: list)

        let listPosition = try await scrollPosition()
        XCTAssertEqual(listPosition, 600)
        XCTAssertFalse(list.visitableView.isShowingScreenshot)
    }

    @MainActor
    func test_reloadAfterBack_rendersTheRevealedPageFresh() async throws {
        let list = await coldBoot("/scroll?page=list")
        try await scroll(to: 600)
        let thread = await push("/scroll?page=thread", over: list)
        await back(from: thread, to: list, whileRevealing: closeKeyboard)

        let reloaded = expectation(description: "The reload rendered")
        list.didRender = { reloaded.fulfill() }
        session.reload()
        await fulfillment(of: [reloaded], timeout: timeout)

        let position = try await scrollPosition()
        XCTAssertEqual(position, 0)
        XCTAssertFalse(list.visitableView.isShowingScreenshot)
        XCTAssertFalse(list.visitableView.activityIndicatorView.isAnimating)
    }

    /// The navigator's recovery: the dead session lets go of the screen, and a
    /// new one adopts it with a replace visit.
    @MainActor
    func test_recoveryAfterBack_rendersTheRevealedPageFresh() async throws {
        let list = await coldBoot("/scroll?page=list")
        try await scroll(to: 600)
        let thread = await push("/scroll?page=thread", over: list)
        await back(from: thread, to: list, whileRevealing: closeKeyboard)

        let retired = session!
        retired.prepareForReplacement()
        retired.webView.stopLoading()
        session = makeSession()
        let recovered = expectation(description: "The recovery rendered")
        list.didRender = { recovered.fulfill() }
        session.restoreVisitable(list)
        await fulfillment(of: [recovered], timeout: timeout)

        XCTAssertIdentical(list.visitableView.webView, session.webView)
        let position = try await scrollPosition()
        XCTAssertEqual(position, 0)
        XCTAssertFalse(list.visitableView.isShowingScreenshot)
        XCTAssertFalse(list.visitableView.activityIndicatorView.isAnimating)
    }

    // MARK: - Navigation

    private let timeout: TimeInterval = 60

    /// What the keyboard does as the web view leaves the popped screen: UIKit
    /// clamps the shared scroll view to the popped page's range without it.
    private let closeKeyboard: (WKWebView) -> Void = { webView in
        webView.scrollView.contentOffset.y = 1200
    }

    @MainActor
    private func coldBoot(_ path: String) async -> BackScrollPage {
        let page = BackScrollPage(url: url(path))
        let rendered = expectation(description: "The cold boot rendered")
        page.didRender = { rendered.fulfill() }
        session.visit(page)
        show(page)
        session.visitableViewWillAppear(page)
        session.visitableViewDidAppear(page)
        await fulfillment(of: [rendered], timeout: timeout)
        page.didRender = nil
        // The bundled Turbo beta predates this optional same-page helper.
        _ = try? await session.webView.evaluateJavaScript("Turbo.navigator.locationWithActionIsSamePage = () => false; true")
        return page
    }

    /// The navigator visits the new screen, then pushes it.
    @MainActor
    private func push(_ path: String, over covered: BackScrollPage) async -> BackScrollPage {
        let page = BackScrollPage(url: url(path))
        let rendered = expectation(description: "The pushed page rendered")
        page.didRender = { rendered.fulfill() }
        session.visit(page)
        session.visitableViewWillDisappear(covered)
        show(page)
        session.visitableViewWillAppear(page)
        session.visitableViewDidDisappear(covered)
        session.visitableViewDidAppear(page)
        await fulfillment(of: [rendered], timeout: timeout)
        page.didRender = nil
        return page
    }

    /// The revealed screen's restore visit starts in its `viewWillAppear`; the pop
    /// finishes once it has rendered.
    @MainActor
    private func back(from popped: BackScrollPage, to revealed: BackScrollPage,
                      whileRevealing reveal: ((WKWebView) -> Void)? = nil) async {
        let rendered = expectation(description: "The revealed page rendered")
        revealed.didRender = { rendered.fulfill() }
        revealed.didActivateWebView = reveal
        session.visitableViewWillDisappear(popped)
        show(revealed)
        session.visitableViewWillAppear(revealed)
        revealed.didActivateWebView = nil
        await fulfillment(of: [rendered], timeout: timeout)
        revealed.didRender = nil
        session.visitableViewDidDisappear(popped)
        session.visitableViewDidAppear(revealed)
    }

    private func show(_ page: BackScrollPage) {
        if page.view.superview == nil {
            page.view.frame = container.view.bounds
            page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.view.addSubview(page.view)
        }
        container.view.bringSubviewToFront(page.view)
    }

    // MARK: - Scrolling

    /// Scrolls the page and waits until Turbo has recorded the position as the
    /// current page's.
    @MainActor
    private func scroll(to y: Int) async throws {
        _ = try await session.webView.evaluateJavaScript("window.scrollTo(0, \(y)); true")
        try await waitUntil("""
            (() => {
              const history = Turbo.navigator.history
              const { scrollPosition } = history.getRestorationDataForIdentifier(history.restorationIdentifier)
              return !!scrollPosition && scrollPosition.y == \(y)
            })()
            """)
    }

    @MainActor
    private func scrollPosition() async throws -> Int {
        let y = try await session.webView.evaluateJavaScript("window.scrollY") as? Double
        return Int((try XCTUnwrap(y)).rounded())
    }

    @MainActor
    private func waitUntil(_ condition: String, timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await session.webView.evaluateJavaScript(condition) as? Bool == true { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for \(condition)")
    }

    // MARK: - Helpers

    private func makeSession() -> Session {
        let session = Session(webView: WKWebView())
        session.delegate = delegate
        return session
    }

    private func url(_ path: String) -> URL {
        URL(string: "http://localhost:\(server.listenAddress.port)\(path)")!
    }
}

private final class BackScrollPage: UIViewController, Visitable {
    weak var visitableDelegate: VisitableDelegate?
    let visitableView = VisitableView(frame: .zero)
    let initialVisitableURL: URL
    var currentVisitableURL: URL { initialVisitableURL }

    var didRender: (() -> Void)?
    var didActivateWebView: ((WKWebView) -> Void)?

    init(url: URL) {
        initialVisitableURL = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = visitableView
    }

    func visitableDidRender() {
        didRender?()
    }

    func visitableWillDeactivateWebView() {}

    func visitableDidActivateWebView(_ webView: WKWebView) {
        didActivateWebView?(webView)
    }
}

private final class BackScrollSessionDelegate: SessionDelegate {
    func session(_ session: Session, didProposeVisit proposal: VisitProposal) {}
    func session(_ session: Session, didProposeVisitToCrossOriginRedirect location: URL) {}
    func sessionWebViewProcessDidTerminate(_ session: Session) {}

    func sessionDidLoadWebView(_ session: Session) {
        session.webView.navigationDelegate = session
    }

    func session(_ session: Session, didFailRequestForVisitable visitable: Visitable, error: HotwireNativeError) {}

    func session(_ session: Session, decidePolicyFor navigationAction: WKNavigationAction) -> WebViewPolicyManager.Decision {
        .allow
    }
}
