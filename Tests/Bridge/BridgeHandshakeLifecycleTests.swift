import Embassy
@testable import HotwireNative
import WebKit
import XCTest

/// Drives a real `Session` against a real server, through the UIKit lifecycle a destination
/// receives when something is presented over it while its page is still loading. The
/// destination's view sits in a visible window, as a screen's does, so the web view is on
/// screen whenever the destination owns it.
@MainActor
final class BridgeHandshakeLifecycleTests: XCTestCase {
    private var eventLoop: SelectorEventLoop!
    private var server: DefaultHTTPServer!
    private var session: Session!
    private var destination: TestBridgeDestination!
    private var window: UIWindow!

    override func setUp() async throws {
        eventLoop = try SelectorEventLoop(selector: KqueueSelector())
        server = DefaultHTTPServer.turboServer(eventLoop: eventLoop)
        try server.start()
        DispatchQueue.global().async { self.eventLoop.runForever() }

        try await WebKitWarmUp.loadOnePageOnScreen(URL(string: "http://localhost:8080/")!)

        Hotwire.registerBridgeComponents([BridgeComponentSpy.self])

        session = Session(webView: Hotwire.config.makeWebView())
        destination = TestBridgeDestination(url: pageURL)

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        destination.view.frame = window.bounds
        window.addSubview(destination.view)
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        server?.stopAndWait()
        eventLoop?.stop()
        Hotwire.registerBridgeComponents([])
    }

    /// The control: nothing covers the destination, so it owns the web view for the whole load.
    func testDestinationStaysOnScreenWhileItsPageLoads() async throws {
        session.visit(destination)
        try await waitForPageScript()
        destination.viewDidAppear(false)

        try await waitForRegisteredComponents()

        let supported = try await evaluate("window.nativeBridge.supportedComponents.join(',')") as? String
        XCTAssertEqual(supported, "two")

        let strandedMessages = try await evaluate("window.webBridge.pendingMessages.length") as? Int
        XCTAssertEqual(strandedMessages, 0)

        XCTAssertNotNil(connectedComponent)
    }

    /// The bug: something is presented over the destination while its page is still loading,
    /// so UIKit sends `viewDidDisappear` and the session hands the web view back. The document
    /// then announces itself to a bridge with no delegate. Returning to the screen re-attaches
    /// the destination and re-shows the rendered page, but recovers no bridge.
    func testDestinationIsCoveredWhileItsPageLoads() async throws {
        session.visit(destination)
        destination.viewDidDisappear(false)

        XCTAssertTrue(destination.visitableDidDeactivateWebViewWasCalled)

        try await waitForPageScript()

        // The document has announced itself while nothing owned the web view, so nothing has
        // registered yet and the page's message waits. Without this the test could re-attach
        // the destination before the announcement and only repeat the control.
        let registeredWhileCovered = try await evaluate("window.nativeBridge.supportedComponents.length") as? Int
        XCTAssertEqual(registeredWhileCovered, 0)

        let queuedWhileCovered = try await evaluate("window.webBridge.pendingMessages.length") as? Int
        XCTAssertEqual(queuedWhileCovered, 1)

        destination.viewDidAppear(false)
        try await waitForRegisteredComponents()

        let supported = try await evaluate("window.nativeBridge.supportedComponents.join(',')") as? String
        XCTAssertEqual(supported, "two")

        let strandedMessages = try await evaluate("window.webBridge.pendingMessages.length") as? Int
        XCTAssertEqual(strandedMessages, 0)

        XCTAssertNotNil(connectedComponent)
    }

    /// Pull to refresh, `Navigator.reload()` and the recovery of a terminated web view all
    /// reload the session under the destination that still owns its web view. The reloaded
    /// document announces itself to that destination, which must register its components
    /// again: nothing of the previous document's registration survives the reload.
    func testDestinationKeepsItsComponentsAcrossAReload() async throws {
        session.visit(destination)
        try await waitForPageScript()
        destination.viewDidAppear(false)
        try await waitForRegisteredComponents()

        _ = try await evaluate("window.loadedBeforeReload = true")
        session.reload()
        try await waitUntil("the reloaded page's script ran") {
            try await self.evaluate("window.loadedBeforeReload === undefined && typeof window.webBridge === 'object'") as? Bool == true
        }
        try await waitForRegisteredComponents()

        let supported = try await evaluate("window.nativeBridge.supportedComponents.join(',')") as? String
        XCTAssertEqual(supported, "two")

        let strandedMessages = try await evaluate("window.webBridge.pendingMessages.length") as? Int
        XCTAssertEqual(strandedMessages, 0)
    }

    // MARK: Private

    /// Non-nil once a component message has actually reached native for this destination.
    private var connectedComponent: BridgeComponentSpy? {
        destination.bridgeDelegate.component()
    }

    private let pageURL = URL(string: "http://localhost:8080/bridge-components")!

    private func waitForPageScript() async throws {
        try await waitUntil("the page's script ran") {
            try await self.evaluate("typeof window.webBridge") as? String == "object"
        }
    }

    /// The register call is made from a detached `Task`, so the JavaScript lands after the
    /// handshake returns. Poll rather than sleep.
    private func waitForRegisteredComponents() async throws {
        try await waitUntil("the destination registered its components") {
            try await self.evaluate("window.nativeBridge.supportedComponents.length") as? Int ?? 0 > 0
        }
    }

    private func evaluate(_ javaScript: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            session.webView.evaluateJavaScript(javaScript) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }
}

/// Polls until `condition` holds, and fails the test once `timeout` passes. Carrying on
/// after a timeout would let the next step run against a page that isn't there.
@MainActor
private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 120,
    _ condition: () async throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if (try? await condition()) == true { return }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw WaitTimeout(description: "Timed out after \(Int(timeout)) seconds waiting until \(description)")
}

private struct WaitTimeout: Error, CustomStringConvertible {
    let description: String
}

/// WebKit loads a page at background priority while its web view is off screen, which is
/// where the covered test's page loads. The first page a freshly booted simulator loads is
/// slow, and at background priority it takes many minutes on CI; later ones are quick. So
/// load one page from the test server in a web view on screen first, once per run, which
/// also starts WebKit's network process at foreground priority.
@MainActor
private enum WebKitWarmUp {
    private static var isWarm = false

    static func loadOnePageOnScreen(_ url: URL) async throws {
        guard !isWarm else { return }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let webView = WKWebView(frame: window.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        webView.load(URLRequest(url: url))
        try await waitUntil("a page loaded on screen", timeout: 600) {
            try await webView.evaluateJavaScript("location.href === '\(url.absoluteString)' && document.readyState === 'complete'") as? Bool == true
        }
        isWarm = true
    }
}

private final class TestBridgeDestination: HotwireWebViewController {
    private(set) var visitableDidDeactivateWebViewWasCalled = false

    override func visitableDidDeactivateWebView() {
        visitableDidDeactivateWebViewWasCalled = true
        super.visitableDidDeactivateWebView()
    }
}
