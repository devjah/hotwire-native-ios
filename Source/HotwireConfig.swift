import SwiftUI
import UIKit
import WebKit

public struct HotwireConfig {
    public typealias WebViewBlock = (_ configuration: WKWebViewConfiguration) -> WKWebView

    /// Set a custom user agent application prefix for every WKWebView instance.
    ///
    /// The library will automatically append a substring to your prefix
    /// which includes:
    /// - "Hotwire Native iOS; Turbo Native iOS;"
    /// - "bridge-components: [your bridge components];"
    ///
    /// WKWebView's default user agent string will also appear at the
    /// beginning of the user agent.
    public var applicationUserAgentPrefix: String? = nil

    /// When enabled, adds a `UIBarButtonItem` of type `.done` to the left
    /// navigation bar button item on screens presented modally.
    public var showDoneButtonOnModals = false

    /// Sets the back button display mode of `HotwireWebViewController`.
    public var backButtonDisplayMode = UINavigationItem.BackButtonDisplayMode.default

    /// Set to true to only show the tab bar on the root screens.
    public var hideTabBarWhenPushed = false

    /// Set to `true` to fade content when performing a `replace` visit.
    public var animateReplaceActions = false

    /// Timeout (in seconds) for the request that resolves redirects before a visit.
    public var redirectResolutionTimeout: TimeInterval = 30

    /// Enable or disable debug logging for Turbo visits and bridge elements
    /// connecting, disconnecting, receiving/sending messages, and more.
    public var debugLoggingEnabled = false {
        didSet {
            HotwireLogger.update(debugLoggingEnabled: debugLoggingEnabled, log: log)
        }
    }

    /// Inject your own logger here to override the default ``enabledLogger``.
    /// This will be used only when ``debugLoggingEnabled``
    /// is set to `true`.
    public var log: Logger? = nil {
        didSet {
            HotwireLogger.update(debugLoggingEnabled: debugLoggingEnabled, log: log)
        }
    }
    
    /// Gets the user agent that the library builds to identify the app
    /// and its registered bridge components.
    ///
    /// The user agent includes:
    /// - Your (optional) custom `applicationUserAgentPrefix`
    /// - "Native iOS; Turbo Native iOS;"
    /// - "bridge-components: [your bridge components];"
    public var userAgent: String {
        get {
            return UserAgent.build(
                applicationPrefix: applicationUserAgentPrefix,
                componentTypes: Hotwire.bridgeComponentTypes
            )
        }
    }

    // MARK: Turbo

    /// Configure options for matching path rules.
    public var pathConfiguration = PathConfiguration()

    /// The view controller used in `Navigator` for web requests. Must be
    /// a `VisitableViewController` or subclass.
    public var defaultViewController: (URL) -> VisitableViewController = { url in
        HotwireWebViewController(url: url)
    }

    /// The navigation controller used in `Navigator` for the main and modal stacks.
    /// Must be a `HotwireNavigationController` or subclass.
    public var defaultNavigationController: () -> UINavigationController = {
        HotwireNavigationController()
    }

    /// Optionally customize the web views used by each Turbo Session.
    /// Ensure you return a new instance each time.
    public var makeCustomWebView: WebViewBlock = { (configuration: WKWebViewConfiguration) in
        let webView = WKWebView.debugInspectable(configuration: configuration)
        // A non-opaque WKWebView keeps a white default `backgroundColor` that
        // the page composites over (washing dark pages grey, tinting light
        // ones), and an opaque one flashes white before first paint. Give it a
        // backing that matches the web app's own page background (`--body-bg`
        // light / `stone-950` dark) so there's neither a cold-boot white flash
        // nor a seam between the top/overscroll gutter and the page content.
        let backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x0C / 255, green: 0x0A / 255, blue: 0x09 / 255, alpha: 1) // stone-950
                : UIColor(red: 0xFC / 255, green: 0xFB / 255, blue: 0xF3 / 255, alpha: 1) // --body-bg
        }
        webView.isOpaque = false
        webView.backgroundColor = backgroundColor
        webView.scrollView.backgroundColor = backgroundColor
        return webView
    }

    /// Optionally customize the native view presented when an error occurs.
    public var makeCustomErrorView: (HotwireNativeError, ErrorPresenter.Handler?) -> any ErrorPresentableView = { error, handler in
        DefaultErrorView(error: error, handler: handler)
    }

    // MARK: Bridge

    /// Set a custom JSON encoder when parsing bridge payloads.
    /// The custom encoder can be useful when you need to apply specific
    /// encoding strategies, like snake case vs. camel case
    public var jsonEncoder = JSONEncoder()

    /// Set a custom JSON decoder when parsing bridge payloads.
    /// The custom decoder can be useful when you need to apply specific
    /// decoding strategies, like snake case vs. camel case
    public var jsonDecoder = JSONDecoder()

    // MARK: - Internal

    public func makeWebView() -> WKWebView {
        let webView = makeCustomWebView(makeWebViewConfiguration())
        
        if !Hotwire.bridgeComponentTypes.isEmpty {
            Bridge.initialize(webView)
        }
        
        return webView
    }

    // MARK: - Private

    private let sharedProcessPool = WKProcessPool()

    var router = Router(
        decisionHandlers: [
            AppNavigationRouteDecisionHandler(),
            SafariViewControllerRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        ]
    )

    var webViewPolicyManager = WebViewPolicyManager(
        policyDecisionHandlers: [
            ReloadWebViewPolicyDecisionHandler(),
            NewWindowWebViewPolicyDecisionHandler(),
            ExternalNavigationWebViewPolicyDecisionHandler(),
            LinkActivatedWebViewPolicyDecisionHandler()
        ]
    )

    // A method (not a property) because we need a new instance for each web view.
    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences?.preferredContentMode = .mobile
        configuration.applicationNameForUserAgent = userAgent
        configuration.processPool = sharedProcessPool
        return configuration
    }
}
