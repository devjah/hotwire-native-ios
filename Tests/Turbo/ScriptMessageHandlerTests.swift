@testable import HotwireNative
import WebKit
import XCTest

final class ScriptMessageHandlerTests: XCTestCase {
    @MainActor
    func test_onlyMainFrameCanSendNativeMessages() async {
        let delegate = MessageRecordingDelegate()
        let observer = FrameMessageObserver()
        let received = expectation(description: "All frame messages were observed")
        received.expectedFulfillmentCount = 4
        observer.onMessage = { received.fulfill() }

        let webView = WKWebView()
        let controller = webView.configuration.userContentController
        for name in ["turbo", "bridge"] {
            controller.add(ScriptMessageHandler(delegate: delegate), name: name)
        }
        controller.add(observer, name: "observed")

        // Both same-origin and sandboxed opaque-origin iframes can access
        // WebKit message handlers even when user scripts are main-frame-only.
        webView.loadHTMLString("""
            <script>
              function post(label) {
                window.webkit.messageHandlers.turbo.postMessage(label);
                window.webkit.messageHandlers.bridge.postMessage(label);
                window.webkit.messageHandlers.observed.postMessage(label);
              }
              post('main');
            </script>
            <iframe srcdoc="<script>
              window.webkit.messageHandlers.turbo.postMessage('iframe');
              window.webkit.messageHandlers.bridge.postMessage('iframe');
              window.webkit.messageHandlers.observed.postMessage('iframe');
            </script>"></iframe>
            <iframe sandbox="allow-scripts" srcdoc="<script>
              window.webkit.messageHandlers.turbo.postMessage('sandbox');
              window.webkit.messageHandlers.bridge.postMessage('sandbox');
              window.webkit.messageHandlers.observed.postMessage('sandbox');
            </script>"></iframe>
            <script>window.onload = () => post('loaded');</script>
            """, baseURL: URL(string: "https://example.com"))

        await fulfillment(of: [received], timeout: 15)
        XCTAssertEqual(observer.mainFrameFlags.filter { $0 }.count, 2)
        XCTAssertEqual(observer.mainFrameFlags.filter { !$0 }.count, 2)
        XCTAssertEqual(delegate.bodies, ["main", "main", "loaded", "loaded"])
        webView.stopLoading()
    }
}

private final class MessageRecordingDelegate: ScriptMessageHandlerDelegate {
    var bodies: [String] = []

    func scriptMessageHandlerDidReceiveMessage(_ scriptMessage: WKScriptMessage) {
        bodies.append(scriptMessage.body as? String ?? "unexpected body")
    }
}

private final class FrameMessageObserver: NSObject, WKScriptMessageHandler {
    var mainFrameFlags: [Bool] = []
    var onMessage: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        mainFrameFlags.append(message.frameInfo.isMainFrame)
        onMessage?()
    }
}
