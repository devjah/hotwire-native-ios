import UIKit
@testable import HotwireNative

/// Manipulate a navigation controller under test.
/// Ensures `viewControllers` is updated synchronously.
/// Manages `presentedViewController` directly because it isn't updated on the same thread.
class TestableNavigationController: HotwireNavigationController {
    override var presentedViewController: UIViewController? {
        get { _presentedViewController }
        set { _presentedViewController = newValue }
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: false)
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        super.popViewController(animated: false)
    }

    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        super.popToRootViewController(animated: false)
    }

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers, animated: false)
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        _presentedViewController = viewControllerToPresent
        super.present(viewControllerToPresent, animated: false, completion: completion)
    }

    /// How many times this controller has dismissed something. Presentation is faked
    /// synchronously here, so a modal that is dismissed and immediately presented
    /// again ends up indistinguishable from one whose content was swapped in place —
    /// the difference only shows in real UIKit, which refuses a present that overlaps
    /// a dismissal. Counting the dismissals lets a test tell the two apart.
    private(set) var dismissCount = 0

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        let dismissedViewController = _presentedViewController
        _presentedViewController = nil
        if dismissedViewController != nil { dismissCount += 1 }
        super.dismiss(animated: false, completion: completion)

        // Simulate UIKit's dismissal lifecycle, which doesn't run synchronously under
        // test: the dismissed controller's `viewDidDisappear` (`isBeingDismissed`)
        // fires its modal dismissal handler.
        (dismissedViewController as? HotwireNavigationController)?.modalDismissalHandler?()
    }

    // MARK: Private

    private var _presentedViewController: UIViewController?
}
