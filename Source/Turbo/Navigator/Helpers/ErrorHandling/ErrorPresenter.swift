import SwiftUI

public protocol ErrorPresenter: UIViewController {
    typealias Handler = () -> Void

    func presentError(_ error: HotwireNativeError, retryHandler: Handler?)
}

public extension ErrorPresenter {
    /// Presents an error in a full screen view.
    /// The error view will display a `Retry` button if `retryHandler != nil`.
    /// Tapping `Retry` will call `retryHandler?()` then dismiss the error.
    ///
    /// - Parameters:
    ///   - error: presents the data in this error
    ///   - retryHandler: a user-triggered action to perform in case the error is recoverable
    ///
    func presentError(_ error: HotwireNativeError, retryHandler: Handler?) {
        // A screen shows one error at a time. A controller that fails again
        // (web view recovery reuses it) would otherwise stack a view over the
        // last, and Retry would remove the one underneath.
        removeErrorViewController()
        let view = Hotwire.config.makeCustomErrorView(error) { [weak self] in
            retryHandler?()
            self?.removeErrorViewController()
        }
        let viewController = ErrorHostingViewController(rootView: AnyView(view))
        addChild(viewController)
        addFullScreenSubview(viewController.view)
        viewController.didMove(toParent: self)
    }

    func removeErrorViewController() {
        for host in children where host is ErrorHostingViewController {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
    }
}

extension UIViewController: ErrorPresenter {}

// MARK: Private

private final class ErrorHostingViewController: UIHostingController<AnyView> {}

private extension UIViewController {
    func addFullScreenSubview(_ subview: UIView) {
        view.addSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
