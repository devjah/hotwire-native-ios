@testable import HotwireNative
import WebKit
import XCTest

final class WebViewBridgeRecoveryTests: XCTestCase {
    @MainActor
    func test_navigationExceptionFromPreviousVisit_doesNotRecoverNewVisit() {
        let webView = DeferredEvaluationWebView()
        let bridge = WebViewBridge(webView: webView)
        let delegate = EvaluationFailureDelegate()
        bridge.delegate = delegate

        bridge.visitLocation(URL(string: "https://example.com/first")!, options: VisitOptions(), restorationIdentifier: nil)
        bridge.visitLocation(URL(string: "https://example.com/second")!, options: VisitOptions(), restorationIdentifier: nil)
        webView.completeFirstWithException()

        XCTAssertEqual(delegate.failureCount, 0)
        webView.completeFirstWithException()
        XCTAssertEqual(delegate.failureCount, 1)
    }

    @MainActor
    func test_navigationExceptionAfterCancellation_doesNotRecover() {
        let webView = DeferredEvaluationWebView()
        let bridge = WebViewBridge(webView: webView)
        let delegate = EvaluationFailureDelegate()
        bridge.delegate = delegate

        bridge.visitLocation(URL(string: "https://example.com/first")!, options: VisitOptions(), restorationIdentifier: nil)
        bridge.cancelVisit(withIdentifier: "first")
        webView.completeFirstWithException()

        XCTAssertEqual(delegate.failureCount, 0)
    }
}

private final class DeferredEvaluationWebView: WKWebView {
    private var completions: [(@MainActor (Any?, Error?) -> Void)] = []

    override func evaluateJavaScript(_ javaScriptString: String,
                                    completionHandler: (@MainActor (Any?, Error?) -> Void)? = nil) {
        if let completionHandler { completions.append(completionHandler) }
    }

    func completeFirstWithException() {
        XCTAssertFalse(completions.isEmpty)
        guard !completions.isEmpty else { return }
        completions.removeFirst()(["error": "navigation failed"], nil)
    }
}

private final class EvaluationFailureDelegate: WebViewDelegate {
    private(set) var failureCount = 0

    func webView(_ webView: WebViewBridge, didFailJavaScriptEvaluationWithError error: Error) {
        failureCount += 1
    }

    func webView(_ webView: WebViewBridge, didProposeVisitToLocation location: URL, options: VisitOptions) {}
    func webViewDidInvalidatePage(_ webView: WebViewBridge) {}
    func webView(_ webView: WebViewBridge, didStartFormSubmissionToLocation location: URL) {}
    func webView(_ webView: WebViewBridge, didFinishFormSubmissionToLocation location: URL) {}
    func webView(_ webView: WebViewBridge, didFailInitialPageLoadWithError: HotwireNativeError) {}
    func webView(_ webView: WebViewBridge, didFailRequestWithNonHttpStatusToLocation location: URL, identifier: String, statusCode: Int) {}
}
