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

    private func makeNavigator(session: Session) -> Navigator {
        Navigator(
            session: session,
            modalSession: Session(webView: Hotwire.config.makeWebView()),
            configuration: .init(name: "", startLocation: URL(string: "https://example.com")!)
        )
    }
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
