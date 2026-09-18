@testable import HotwireNative
import WebKit
import XCTest

/// The pull-to-refresh control belongs to the web view's scroll view, which
/// keeps it centred. Installed as a constrained subview instead, its frame was
/// left to a fight between Auto Layout and UIKit's own refresh-control
/// management; on iOS 27 UIKit won, with x = 0 and a width of 0 the moment
/// refreshing began, and the spinner spun half off the screen's left edge.
final class VisitableViewRefreshControlTests: XCTestCase {
    private var window: UIWindow!
    private var controller: VisitableViewController!
    private var webView: WKWebView!

    override func setUp() {
        controller = VisitableViewController(url: URL(string: "http://localhost/")!)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false // as Session does
        controller.visitableView.activateWebView(webView, forVisitable: controller)
        window.layoutIfNeeded()
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
    }

    func test_activating_handsTheControlToTheScrollView() {
        XCTAssertTrue(webView.scrollView.refreshControl === controller.visitableView.refreshControl)
        XCTAssertTrue(controller.visitableView.refreshControl.translatesAutoresizingMaskIntoConstraints,
                      "UIKit manages the frame; constraints would fight it")
    }

    func test_refreshing_keepsTheSpinnerCentred() {
        let control = controller.visitableView.refreshControl
        control.beginRefreshing()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        window.layoutIfNeeded()

        let frame = control.convert(control.bounds, to: nil)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertEqual(frame.midX, window.bounds.midX, accuracy: 1,
                       "the spinner is centred in the control, so an off-centre control puts it off-screen")
    }

    func test_deactivating_takesTheControlBack() {
        controller.visitableView.deactivateWebView()

        XCTAssertNil(webView.scrollView.refreshControl)
        XCTAssertNil(controller.visitableView.refreshControl.superview)
    }

    func test_disablingPullToRefresh_takesTheControlBack() {
        controller.visitableView.allowsPullToRefresh = false
        XCTAssertNil(webView.scrollView.refreshControl)

        controller.visitableView.allowsPullToRefresh = true
        XCTAssertTrue(webView.scrollView.refreshControl === controller.visitableView.refreshControl)
    }
}
