import UIKit
import WebKit

open class VisitableView: UIView {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        installActivityIndicatorView()
    }

    // MARK: Web View

    open var webView: WKWebView?
    private weak var visitable: Visitable?

    open func activateWebView(_ webView: WKWebView, forVisitable visitable: Visitable) {
        self.webView = webView
        self.visitable = visitable
        // iOS 14 fallback: with no explicit contentScrollView, UIKit's heuristic requires
        // the scrollable view to be the first subview for large-title / tab-bar-minimize
        // to work. On iOS 15+ this is made robust by setContentScrollView in Visitable.
        insertSubview(webView, at: 0)
        addFillConstraints(for: webView)
        installRefreshControl()
        showOrHideWebView()
    }

    open func deactivateWebView() {
        removeRefreshControl()
        webView?.removeFromSuperview()
        webView = nil
        visitable = nil
    }

    private func showOrHideWebView() {
        webView?.isHidden = isShowingScreenshot
    }

    // MARK: Refresh Control

    open lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)
        return refreshControl
    }()

    open var allowsPullToRefresh: Bool = true {
        didSet {
            if allowsPullToRefresh {
                installRefreshControl()
            } else {
                removeRefreshControl()
            }
        }
    }

    open var isRefreshing: Bool {
        refreshControl.isRefreshing
    }

    /// The scroll view owns the control's frame. It used to be added as a plain
    /// subview with Auto Layout constraints (centred on this view, pinned to the
    /// safe-area top, no width), which fought UIKit's own management: a scroll
    /// view adopts a `UIRefreshControl` subview as its `refreshControl` and, the
    /// moment a refresh begins, sets the frame itself. On iOS 27 that frame
    /// lands at x = 0 with the zero width the constraints had left it, so the
    /// spinner spun centred on the screen's left edge, half cut off. Handing the
    /// control over through the property is the documented path since iOS 10:
    /// UIKit keeps it centred, just above the content and below the adjusted
    /// content inset, on every release.
    private func installRefreshControl() {
        guard let scrollView = webView?.scrollView, allowsPullToRefresh else { return }

        #if !targetEnvironment(macCatalyst)
        scrollView.refreshControl = refreshControl
        #endif
    }

    private func removeRefreshControl() {
        refreshControl.endRefreshing()
        if let scrollView = webView?.scrollView, scrollView.refreshControl === refreshControl {
            scrollView.refreshControl = nil
        }
        refreshControl.removeFromSuperview()
    }

    @objc func refresh(_ sender: AnyObject) {
        visitable?.visitableViewDidRequestRefresh()
    }

    // MARK: Activity Indicator

    open lazy var activityIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.color = UIColor.gray
        view.hidesWhenStopped = true
        return view
    }()

    private func installActivityIndicatorView() {
        addSubview(activityIndicatorView)
        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    open func showActivityIndicator() {
        guard !isRefreshing else { return }

        activityIndicatorView.startAnimating()
        bringSubviewToFront(activityIndicatorView)
    }

    open func hideActivityIndicator() {
        activityIndicatorView.stopAnimating()
    }

    // MARK: Screenshots

    private lazy var screenshotContainerView: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = self.backgroundColor
        return view
    }()

    private var screenshotView: UIView?

    var isShowingScreenshot: Bool {
        screenshotContainerView.superview != nil
    }

    open func updateScreenshot() {
        guard !isShowingScreenshot, let webView = webView, let screenshot = webView.snapshotView(afterScreenUpdates: false) else { return }

        screenshotView?.removeFromSuperview()
        screenshot.translatesAutoresizingMaskIntoConstraints = false
        screenshotContainerView.addSubview(screenshot)

        NSLayoutConstraint.activate([
            screenshot.centerXAnchor.constraint(equalTo: screenshotContainerView.centerXAnchor),
            screenshot.topAnchor.constraint(equalTo: screenshotContainerView.topAnchor),
            screenshot.widthAnchor.constraint(equalToConstant: screenshot.bounds.size.width),
            screenshot.heightAnchor.constraint(equalToConstant: screenshot.bounds.size.height)
        ])

        screenshotView = screenshot
    }

    open func showScreenshot() {
        guard !isShowingScreenshot, !isRefreshing else { return }

        addSubview(screenshotContainerView)
        addFillConstraints(for: screenshotContainerView)
        showOrHideWebView()
    }

    open func hideScreenshot() {
        screenshotContainerView.removeFromSuperview()
        showOrHideWebView()
    }

    open func clearScreenshot() {
        screenshotView?.removeFromSuperview()
    }

    // MARK: - Constraints

    private func addFillConstraints(for view: UIView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
