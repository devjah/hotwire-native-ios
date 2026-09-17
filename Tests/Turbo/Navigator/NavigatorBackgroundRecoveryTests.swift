@testable import HotwireNative
import UIKit
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
///
/// And it drains at neither moment unless the app is actually active — see
/// `Navigator.inspectAllSessions`, and the tests at the foot of this file.
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

    // MARK: - Nothing starts a visit while the app is not active

    /// The blank tab with a spinner on it, and the reason this gate exists.
    ///
    /// `UIApplication.willEnterForegroundNotification` is delivered for wakes
    /// nobody is looking at — a Live Activity update, a tap on the Lock Screen
    /// that stops at the passcode, an app-switcher snapshot — and those never
    /// become active. Draining the queue there starts a `ColdBootVisit` into a
    /// WebContent process the system is about to suspend: the load never
    /// commits, `Session.reload` has already put a screenshot and a spinner
    /// over the web view, and the app is suspended in that state. Measured on
    /// an iPhone (2026-09-17): the visit started 1.7 s after the scene was back
    /// in the background and the page sat behind that spinner for 36 minutes.
    func test_appWillEnterForeground_whileNotActive_doesNotReloadOrDrainTheQueue() {
        let session = ReloadRecordingSession(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session, appState: .background)

        navigator.backgroundTerminatedWebViewSessions.append(session)

        navigator.appWillEnterForeground()

        XCTAssertEqual(session.reloadCallCount, 0,
                       "a visit must not be started while the app is in the background")
        XCTAssertEqual(navigator.backgroundTerminatedWebViewSessions.count, 1,
                       "the queue must survive a wake that never became active, for the next real open")
    }

    /// The deferral is not a loss: the very next `didBecomeActive` — which
    /// follows any real open within milliseconds — does the work.
    func test_aWakeThatNeverBecameActive_isRecoveredAtTheNextRealOpen() {
        let session = ReloadRecordingSession(webView: Hotwire.config.makeWebView())
        var state = UIApplication.State.background
        let navigator = makeNavigator(session: session, appState: { state })

        navigator.backgroundTerminatedWebViewSessions.append(session)
        navigator.appWillEnterForeground()
        XCTAssertEqual(session.reloadCallCount, 0)

        state = .active
        navigator.appDidBecomeActive()

        XCTAssertTrue(navigator.backgroundTerminatedWebViewSessions.isEmpty)
        XCTAssertEqual(session.reloadCallCount, 1, "the queued session is reloaded once, when someone is looking")
    }

    /// `.inactive` is the same answer as `.background`: behind the passcode
    /// screen, mid-transition or under the app switcher, a visit is just as
    /// stranded and the person cannot see the page either way.
    func test_appWillEnterForeground_whileInactive_doesNotStartAVisit() {
        let session = ReloadRecordingSession(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session, appState: .inactive)

        navigator.backgroundTerminatedWebViewSessions.append(session)

        navigator.appWillEnterForeground()

        XCTAssertEqual(session.reloadCallCount, 0)
        XCTAssertEqual(navigator.backgroundTerminatedWebViewSessions.count, 1)
    }

    /// The silently-relaunched shapes are gated by the same rule: recreating a
    /// session is a visit too (`route` → cold boot), so it waits for active.
    func test_aURLLessSessionIsNotRecreatedWhileNotActive() {
        let session = VisitedSessionDouble(webView: Hotwire.config.makeWebView())
        let navigator = makeNavigator(session: session, appState: .background)

        navigator.appWillEnterForeground()

        XCTAssertTrue(navigator.session === session,
                      "a web view must not be recreated while the app is in the background")
    }

    private func makeNavigator(session: Session,
                               appState: UIApplication.State = .active) -> Navigator {
        makeNavigator(session: session, appState: { appState })
    }

    private func makeNavigator(session: Session,
                               appState: @escaping () -> UIApplication.State) -> Navigator {
        Navigator(
            session: session,
            modalSession: Session(webView: Hotwire.config.makeWebView()),
            configuration: .init(name: "", startLocation: URL(string: "https://example.com")!),
            appState: appState
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
