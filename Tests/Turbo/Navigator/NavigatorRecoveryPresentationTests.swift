@testable import HotwireNative
import UIKit
import WebKit
import XCTest

final class NavigatorRecoveryPresentationTests: XCTestCase {
    private var originalWebViewFactory: HotwireConfig.WebViewBlock!

    override func setUp() {
        originalWebViewFactory = Hotwire.config.makeCustomWebView
        Hotwire.config.makeCustomWebView = { RecoveryWebView(frame: .zero, configuration: $0) }
    }

    override func tearDown() {
        Hotwire.config.makeCustomWebView = originalWebViewFactory
    }

    func test_mainRecovery_preservesPresentedFormAndExistingController() throws {
        let navigator = makeNavigator()
        let originalSession = navigator.session
        let page = seedVisit(in: originalSession, on: navigator.rootViewController)
        let form = UIViewController()
        navigator.modalRootViewController.setViewControllers([form], animated: false)
        navigator.rootViewController.present(navigator.modalRootViewController, animated: false)

        navigator.appDidBecomeActive()

        XCTAssertNotIdentical(navigator.session, originalSession)
        XCTAssertIdentical(navigator.rootViewController.presentedViewController, navigator.modalRootViewController)
        XCTAssertIdentical(navigator.modalRootViewController.topViewController, form)
        XCTAssertIdentical(navigator.rootViewController.topViewController, page)
        XCTAssertIdentical(navigator.session.activeVisitable, page)
        XCTAssertIdentical(navigator.session.topmostVisitable, page)
        XCTAssertNil(originalSession.webView.superview, "The dead web view must be detached before reusing its controller")
        XCTAssertIdentical(page.visitableView.webView, navigator.session.webView)
        XCTAssertNil(originalSession.topmostVisitable)
        // A retained retry callback must not let the retired session take the
        // controller back from its replacement.
        originalSession.reload()
        originalSession.visit(page, reload: true)
        XCTAssertIdentical(page.visitableView.webView, navigator.session.webView)
        let retiredWebView = try XCTUnwrap(originalSession.webView as? RecoveryWebView)
        XCTAssertEqual(retiredWebView.requests.count, 1)
    }

    func test_modalRecovery_preservesItsContextWithoutReapplyingPathRules() {
        let navigator = makeNavigator()
        let mainController = UIViewController()
        navigator.rootViewController.setViewControllers([mainController], animated: false)
        let originalSession = navigator.modalSession
        let page = seedVisit(in: originalSession, on: navigator.modalRootViewController)
        navigator.rootViewController.present(navigator.modalRootViewController, animated: false)

        // The original proposal supplied modal context; no path rule supplies it.
        navigator.appDidBecomeActive()

        XCTAssertNotIdentical(navigator.modalSession, originalSession)
        XCTAssertIdentical(navigator.rootViewController.presentedViewController, navigator.modalRootViewController)
        XCTAssertIdentical(navigator.rootViewController.topViewController, mainController)
        XCTAssertIdentical(navigator.modalRootViewController.topViewController, page)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, page)
        XCTAssertIdentical(navigator.modalSession.topmostVisitable, page)
    }

    func test_recovery_reloadsCurrentLocationAndSupportsAnotherReload() throws {
        let navigator = makeNavigator()
        let page = seedVisit(in: navigator.session, on: navigator.rootViewController)
        let currentURL = URL(string: "https://example.com/current")!
        page.currentVisitableURL = currentURL

        navigator.appDidBecomeActive()

        let webView = try XCTUnwrap(navigator.session.webView as? RecoveryWebView)
        XCTAssertEqual(webView.requests, [currentURL])
        navigator.session.reload()
        XCTAssertEqual(webView.requests, [currentURL, currentURL])
        XCTAssertIdentical(navigator.rootViewController.topViewController, page)
    }

    func test_mainRecovery_backNavigationUsesReplacementSession() {
        assertBackNavigationAfterRecovery(modal: false)
    }

    func test_modalRecovery_backNavigationUsesReplacementSession() {
        assertBackNavigationAfterRecovery(modal: true)
    }

    private func assertBackNavigationAfterRecovery(modal: Bool) {
        let navigator = makeNavigator()
        let originalSession = modal ? navigator.modalSession : navigator.session
        let navigationController = modal ? navigator.modalRootViewController : navigator.rootViewController
        let previousPage = seedVisit(in: originalSession, on: navigationController)
        let page = TestVisitable(url: URL(string: "https://example.com/next")!)
        originalSession.visit(page)
        navigationController.setViewControllers([previousPage, page], animated: false)
        originalSession.visitableViewDidAppear(page)
        if modal {
            navigator.rootViewController.present(navigator.modalRootViewController, animated: false)
        }

        navigator.appDidBecomeActive()
        let replacement = modal ? navigator.modalSession : navigator.session
        XCTAssertNotIdentical(replacement, originalSession)
        XCTAssertIdentical(previousPage.visitableDelegate, replacement)

        navigationController.popViewController(animated: false)
        previousPage.visitableDelegate?.visitableViewWillAppear(previousPage)
        previousPage.visitableDelegate?.visitableViewDidAppear(previousPage)

        XCTAssertIdentical(replacement.activeVisitable, previousPage)
        XCTAssertIdentical(previousPage.visitableView.webView, replacement.webView)
    }

    private func makeNavigator() -> Navigator {
        let navigator = Navigator(
            session: Session(webView: Hotwire.config.makeWebView()),
            modalSession: Session(webView: Hotwire.config.makeWebView()),
            configuration: .init(name: "Recovery", startLocation: URL(string: "https://example.com")!),
            appState: { .active }
        )
        navigator.hierarchyController = NavigationHierarchyController(
            delegate: navigator,
            navigationController: TestableNavigationController(),
            modalNavigationController: TestableNavigationController()
        )
        return navigator
    }

    private func seedVisit(in session: Session, on navigationController: UINavigationController) -> TestVisitable {
        let page = TestVisitable(url: URL(string: "https://example.com/original")!)
        navigationController.setViewControllers([page], animated: false)
        session.visit(page)
        session.visitableViewDidAppear(page)
        return page
    }
}

private final class RecoveryWebView: WKWebView {
    private(set) var requests: [URL] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request.url!)
        return nil
    }

    override func evaluateJavaScript(_ javaScriptString: String,
                                    completionHandler: (@MainActor (Any?, Error?) -> Void)? = nil) {
        completionHandler?(nil, nil)
    }
}
