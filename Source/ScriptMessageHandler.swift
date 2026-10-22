import WebKit

protocol ScriptMessageHandlerDelegate: AnyObject {
    func scriptMessageHandlerDidReceiveMessage(_ scriptMessage: WKScriptMessage)
}

// Avoids retain cycle caused by WKUserContentController
final class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: ScriptMessageHandlerDelegate?

    init(delegate: ScriptMessageHandlerDelegate?) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive scriptMessage: WKScriptMessage) {
        // Message handlers are exposed to subframes even when the bridge's
        // user scripts are injected only into the main frame.
        guard scriptMessage.frameInfo.isMainFrame else { return }
        delegate?.scriptMessageHandlerDidReceiveMessage(scriptMessage)
    }
}
