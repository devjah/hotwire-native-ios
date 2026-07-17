@testable import HotwireNative
import WebKit
import XCTest

/// Verifies that sessions whose web content process was terminated while the app
/// was backgrounded are reloaded when the app returns to the foreground.
///
/// iOS reclaims WKWebView web content processes from suspended apps and reports
/// the termination during the foregrounding window, while `applicationState` is
/// still `.background`. `reloadIfPermitted` therefore can't reload immediately —
/// it queues the session in `backgroundTerminatedWebViewSessions` to reload once
/// foregrounded. Upstream only drains that queue on `appWillEnterForeground`,
/// which can fire *before* the termination is reported, orphaning the session
/// and leaving a blank web view until a manual refresh. This fork also drains on
/// `appDidBecomeActive` to catch that case.
final class NavigatorBackgroundRecoveryTests: XCTestCase {
    /// The fix: a session terminated while backgrounded is reloaded on
    /// `appDidBecomeActive`. Without this drain the session stays queued and the
    /// web view stays blank.
    func test_appDidBecomeActive_reloadsBackgroundTerminatedSessions() {
        let session = ReloadRecordingSession(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session)

        // Simulate a termination reported while the app was backgrounded:
        // reloadIfPermitted queues the session rather than reloading it.
        navigator.backgroundTerminatedWebViewSessions.append(session)
        XCTAssertEqual(session.reloadCallCount, 0, "queued session must not reload until foreground")

        navigator.appDidBecomeActive()

        XCTAssertTrue(navigator.backgroundTerminatedWebViewSessions.isEmpty,
                      "appDidBecomeActive should drain the background-terminated session queue")
        XCTAssertEqual(session.reloadCallCount, 1, "the queued session should be reloaded exactly once")
    }

    /// Regression guard for the pre-existing path: the queue is still drained on
    /// `appWillEnterForeground` too.
    func test_appWillEnterForeground_reloadsBackgroundTerminatedSessions() {
        let session = ReloadRecordingSession(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session)

        navigator.backgroundTerminatedWebViewSessions.append(session)

        navigator.appWillEnterForeground()

        XCTAssertTrue(navigator.backgroundTerminatedWebViewSessions.isEmpty)
        XCTAssertEqual(session.reloadCallCount, 1)
    }

    /// A session that wasn't terminated in the background is left untouched on
    /// foreground (no spurious reloads that would discard scroll/form state).
    func test_appDidBecomeActive_doesNotReloadHealthySessions() {
        let session = ReloadRecordingSession(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session)

        // Empty queue: nothing was terminated while backgrounded.
        navigator.appDidBecomeActive()

        XCTAssertEqual(session.reloadCallCount, 0)
    }

    /// A reclaimed WebContent process can also be relaunched silently with the
    /// web view's `url` reset to nil. JS probes can't detect that shape (the
    /// fresh context evaluates fine and there is no original URL left to
    /// compare against), so `inspect()` must recreate the session outright.
    func test_appDidBecomeActive_recreatesVisitedSessionWhoseWebViewLostItsURL() {
        let session = VisitedSessionDouble(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session)

        navigator.appDidBecomeActive()

        XCTAssertFalse(navigator.session === session,
                       "a visited session whose web view has url == nil and no load in flight should be recreated")
    }

    /// The nil-URL check must not fire while a load is in flight — the web view
    /// legitimately has no URL until the navigation commits.
    func test_appDidBecomeActive_leavesLoadingSessionsAlone() {
        let webView = LoadingStubWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let session = VisitedSessionDouble(webView: webView)
        let navigator = makeNavigator(session: session)

        navigator.appDidBecomeActive()

        XCTAssertTrue(navigator.session === session,
                      "a session mid-load must not be recreated")
    }

    /// The nil-URL check must not fire for a session that never visited a page
    /// — a fresh web view legitimately has no URL.
    func test_appDidBecomeActive_leavesNeverVisitedSessionsAlone() {
        let session = Session(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session)

        navigator.appDidBecomeActive()

        XCTAssertTrue(navigator.session === session,
                      "a session with no topmost visitable must not be recreated")
    }

    private func makeNavigator(session: Session) -> Navigator {
        Navigator(
            session: session,
            modalSession: Session(webView: Hotwire.config.makeWebView()),
            configuration: .init(name: "", startLocation: URL(string: "https://example.com")!)
        )
    }
}

/// Session double that reports a completed visit natively (`topmostVisitable`
/// and `activeVisitable` set) while its web view holds whatever state the test
/// gives it — used to simulate the silent-relaunch states `inspect()` handles.
private final class VisitedSessionDouble: Session {
    let visitable = TestVisitable(url: URL(string: "https://example.com/page")!)

    override var topmostVisitable: Visitable? { visitable }
    override var activeVisitable: Visitable? { visitable }
}

/// Web view stub that pretends a load is in flight.
private final class LoadingStubWebView: WKWebView {
    override var isLoading: Bool { true }
}

/// Session double that records `reload()` calls. `super.reload()` is a safe
/// no-op here because there is no `topmostVisitable`.
private final class ReloadRecordingSession: Session {
    private(set) var reloadCallCount = 0

    override func reload() {
        reloadCallCount += 1
        super.reload()
    }
}
