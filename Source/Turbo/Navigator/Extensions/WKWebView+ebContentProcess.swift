import Foundation
import WebKit

enum WebContentProcessState {
    case active
    case terminated
}

extension WKWebView {
    /// Queries the state of the web content process asynchronously.
    ///
    /// This method evaluates a simple JavaScript function in the web view to determine if the web content process is active.
    ///
    /// - Parameter completionHandler: A closure to be called when the query completes. The closure takes a single argument representing the state of the web content process.
    ///
    /// - Note: The web content process is considered active if the JavaScript evaluation succeeds without error.
    /// If an error occurs during evaluation, the process is considered terminated.
    ///
    /// A successful evaluation is not enough on its own: when iOS reclaims the
    /// WebContent process of a suspended app, WebKit can relaunch it lazily and
    /// silently (no `webViewWebContentProcessDidTerminate`), leaving a fresh
    /// `about:blank` context in which JavaScript evaluates fine — while
    /// `webView.url` still reports the original page and the view renders
    /// white. Detect that mismatch and report it as terminated too.
    func queryWebContentProcessState(completionHandler: @escaping (WebContentProcessState) -> Void) {
        evaluateJavaScript("location.href") { [weak self] value, error in
            if error != nil {
                completionHandler(.terminated)
                return
            }

            if let self,
               let href = value as? String, href == "about:blank",
               let url = self.url, url.absoluteString != "about:blank",
               !self.isLoading {
                completionHandler(.terminated)
                return
            }

            completionHandler(.active)
        }
    }
}
