import SafariServices
import UIKit
import WebKit

class NavigationHierarchyController {
    let navigationController: UINavigationController
    let modalNavigationController: UINavigationController

    /// Stacked modal navigation controllers presented on top of `modalNavigationController`
    /// via the `modal_presentation: "stack"` path property. The last element is the topmost.
    private(set) var stackedModalNavigationControllers: [UINavigationController] = []

    /// The most recently presented modal navigation controller, or the root modal
    /// navigation controller when no stacked modals are presented.
    var topmostModalNavigationController: UINavigationController {
        stackedModalNavigationControllers.last ?? modalNavigationController
    }

    var rootViewController: UIViewController { navigationController }
    var activeNavigationController: UINavigationController {
        navigationController.presentedViewController != nil ? topmostModalNavigationController : navigationController
    }

    enum NavigationStackType {
        case main
        case modal
    }

    func navController(for navigationType: NavigationStackType) -> UINavigationController {
        switch navigationType {
        case .main: navigationController
        case .modal: topmostModalNavigationController
        }
    }

    init(
        delegate: NavigationHierarchyControllerDelegate,
        navigationController: UINavigationController = Hotwire.config.defaultNavigationController(),
        modalNavigationController: UINavigationController = Hotwire.config.defaultNavigationController()
    ) {
        self.delegate = delegate
        self.navigationController = navigationController
        self.modalNavigationController = modalNavigationController

        // If the root modal is dismissed outside of this class's control, any stacked
        // modals above it are gone too — don't keep stale references around.
        (modalNavigationController as? HotwireNavigationController)?.modalDismissalHandler = { [weak self] in
            self?.clearStackedModals()
        }
    }

    func route(controller: UIViewController, proposal: VisitProposal) {
        if let alert = controller as? UIAlertController {
            presentAlert(alert, via: proposal)
        } else {
            if let visitable = controller as? Visitable {
                visitable.visitableView.allowsPullToRefresh = proposal.pullToRefreshEnabled
            }

            dismissModalIfNeeded(for: proposal)

            switch proposal.presentation {
            case .default:
                navigate(with: controller, via: proposal)
            case .pop:
                pop(animated: proposal.animated)
            case .replace:
                replace(with: controller, via: proposal)
            case .refresh:
                refresh(via: proposal)
            case .clearAll:
                clearAll(animated: proposal.animated)
            case .replaceRoot:
                replaceRoot(with: controller, via: proposal)
            case .none:
                break // Do nothing.
            }
        }
    }

    func pop(animated: Bool) {
        if let topStackedModal = stackedModalNavigationControllers.last {
            if topStackedModal.viewControllers.count == 1 {
                dismissTopmostStackedModal(animated: animated)
            } else {
                topStackedModal.popViewController(animated: animated)
            }
        } else if navigationController.presentedViewController != nil && !modalNavigationController.isBeingDismissed {
            if modalNavigationController.viewControllers.count == 1 {
                navigationController.dismiss(animated: animated)
            } else {
                modalNavigationController.popViewController(animated: animated)
            }
        } else {
            navigationController.popViewController(animated: animated)
        }
    }

    func clearAll(animated: Bool) {
        dismissEntireModalContext(animated: animated)
        navigationController.popToRootViewController(animated: animated)
        refreshIfTopViewControllerIsVisitable(from: .main)
    }

    // MARK: Private

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private unowned let delegate: NavigationHierarchyControllerDelegate

    private func presentAlert(_ alert: UIAlertController, via proposal: VisitProposal) {
        if navigationController.presentedViewController != nil {
            topmostModalNavigationController.present(alert, animated: proposal.animated)
        } else {
            navigationController.present(alert, animated: proposal.animated)
        }
    }
    
    private var isInModalContext: Bool {
        navigationController.presentedViewController != nil
        && !modalNavigationController.isBeingDismissed
    }

    private func navigate(with controller: UIViewController, via proposal: VisitProposal) {
        switch proposal.context {
        case .default:
            if let visitable = controller as? Visitable {
                delegate.visit(visitable, on: .main, with: proposal.options)
            }
            let willReplaceModalContext = isInModalContext
            dismissEntireModalContext(animated: proposal.animated)
            pushOrReplace(on: navigationController,
                          with: controller,
                          via: proposal,
                          didReplaceModalContext: willReplaceModalContext)
        case .modal:
            if let visitable = controller as? Visitable {
                delegate.visit(visitable, on: .modal, with: proposal.options)
            }
            controller.configureModalBehaviour(with: proposal)

            if isInModalContext {
                if let revealTarget = navControllerBeneathTopmostStackedModal(matching: proposal) {
                    // Navigating back to a screen covered by stacked modal(s), e.g. via
                    // `history.back()` from a stacked modal: dismiss everything above it.
                    dismissStackedModals(above: revealTarget, animated: proposal.animated)
                } else if proposal.modalPresentation == .stack,
                          !visitingSamePage(on: topmostModalNavigationController, with: controller, via: proposal),
                          !visitingPreviousPage(on: topmostModalNavigationController, with: controller, via: proposal) {
                    // The previous-page guard keeps a back-navigation to a stack-tagged
                    // page (e.g. from a screen pushed inside the sheet back to the
                    // sheet's root) popping within the sheet instead of stacking a
                    // duplicate sheet on top.
                    presentStackedModal(with: controller, via: proposal)
                } else {
                    pushOrReplace(on: topmostModalNavigationController, with: controller, via: proposal)
                }
            } else {
                modalNavigationController.setViewControllers([controller], animated: proposal.animated)
                modalNavigationController.setModalPresentationStyle(via: proposal)
                navigationController.present(modalNavigationController, animated: proposal.animated)
            }
        }
    }

    private func pushOrReplace(on navigationController: UINavigationController,
                               with controller: UIViewController,
                               via proposal: VisitProposal,
                               didReplaceModalContext: Bool = false) {
        if visitingSamePage(on: navigationController, with: controller, via: proposal) {
            navigationController.replaceLastViewController(with: controller)
        } else if visitingPreviousPage(on: navigationController, with: controller, via: proposal) {
            navigationController.popViewController(animated: proposal.animated)
        } else if proposal.options.action == .advance || didReplaceModalContext {
            navigationController.pushViewController(controller, animated: proposal.animated)
        } else {
            navigationController.replaceLastViewController(with: controller)
        }
    }

    private func visitingSamePage(on navigationController: UINavigationController,
                                  with controller: UIViewController,
                                  via proposal: VisitProposal) -> Bool {
        if let visitable = navigationController.topViewController as? Visitable {
            return visitable.initialVisitableURL.isSameLocation(as: proposal.url, pathProperties: proposal.properties)
        } else if let topViewController = navigationController.topViewController {
            return topViewController.isMember(of: type(of: controller))
        }
        return false
    }

    private func visitingPreviousPage(on navigationController: UINavigationController,
                                      with controller: UIViewController,
                                      via proposal: VisitProposal) -> Bool {
        guard navigationController.viewControllers.count >= 2 else { return false }

        let previousController = navigationController.viewControllers[navigationController.viewControllers.count - 2]
        if let previousVisitable = previousController as? VisitableViewController {
            return previousVisitable.initialVisitableURL.isSameLocation(as: proposal.url, pathProperties: proposal.properties)
        }
        return type(of: previousController) == type(of: controller)
    }

    private func replace(with controller: UIViewController, via proposal: VisitProposal) {
        switch proposal.context {
        case .default:
            if let visitable = controller as? Visitable {
                delegate.visit(visitable, on: .main, with: proposal.options)
            }
            dismissEntireModalContext(animated: proposal.animated)
            navigationController.replaceLastViewController(with: controller)
        case .modal:
            if let visitable = controller as? Visitable {
                delegate.visit(visitable, on: .modal, with: proposal.options)
            }
            controller.configureModalBehaviour(with: proposal)

            if navigationController.presentedViewController != nil {
                // `modal_presentation: stack` is intentionally ignored for
                // `presentation: replace` — the replacement happens in place
                // on the topmost modal.
                topmostModalNavigationController.replaceLastViewController(with: controller)
            } else {
                modalNavigationController.setViewControllers([controller], animated: false)
                modalNavigationController.setModalPresentationStyle(via: proposal)
                navigationController.present(modalNavigationController, animated: proposal.animated)
            }
        }
    }

    private func refresh(via proposal: VisitProposal) {
        if proposal.isHistoricalLocation {
            refreshIfTopViewControllerIsVisitable(from: .main)
            return
        }

        if let topStackedModal = stackedModalNavigationControllers.last {
            if topStackedModal.viewControllers.count == 1 {
                // Reactivating the revealed visitable issues the same `.restore`
                // visit a refresh would, so no explicit refresh is needed here.
                dismissTopmostStackedModal(animated: proposal.animated)
            } else {
                topStackedModal.popViewController(animated: proposal.animated)
                refreshIfTopViewControllerIsVisitable(from: .modal)
            }
            return
        }

        if navigationController.presentedViewController != nil {
            if modalNavigationController.viewControllers.count == 1 {
                navigationController.dismiss(animated: proposal.animated)
                refreshIfTopViewControllerIsVisitable(from: .main)
            } else {
                modalNavigationController.popViewController(animated: proposal.animated)
                refreshIfTopViewControllerIsVisitable(from: .modal)
            }
            return
        }

        navigationController.popViewController(animated: proposal.animated)
        refreshIfTopViewControllerIsVisitable(from: .main)
    }

    private func replaceRoot(with controller: UIViewController, via proposal: VisitProposal) {
        if let visitable = controller as? Visitable {
            delegate.visit(visitable, on: .main, with: .init(action: .replace))
        }

        dismissEntireModalContext(animated: proposal.animated)
        navigationController.setViewControllers([controller], animated: proposal.animated)
    }
    
    private func refreshIfTopViewControllerIsVisitable(from stack: NavigationStackType) {
        if let navControllerTopmostVisitable = navController(for: stack).topViewController as? Visitable {
            delegate.refreshVisitable(navigationStack: stack,
                                                  newTopmostVisitable: navControllerTopmostVisitable)
        }
    }

    private func dismissModalIfNeeded(for visit: VisitProposal) {
        // The desired behaviour for historical location visits is
        // to always dismiss the "modal" stack.
        let dismissModal = visit.isHistoricalLocation && navigationController.presentedViewController != nil
        guard dismissModal else { return }

        dismissEntireModalContext(animated: visit.animated)
    }

    // MARK: Stacked modals

    private func presentStackedModal(with controller: UIViewController, via proposal: VisitProposal) {
        let stackedModal = Hotwire.config.defaultNavigationController()
        stackedModal.setViewControllers([controller], animated: false)
        stackedModal.setModalPresentationStyle(via: proposal)

        if let hotwireStackedModal = stackedModal as? HotwireNavigationController {
            hotwireStackedModal.modalDismissalHandler = { [weak self, weak stackedModal] in
                guard let self, let stackedModal else { return }
                self.stackedModalDidDismiss(stackedModal)
            }
        } else {
            logger.warning("Stacked modal dismissal detection requires a HotwireNavigationController. Return a HotwireNavigationController subclass from Hotwire.config.defaultNavigationController to support interactive or app-initiated dismissal.")
        }

        let presenter = topmostModalNavigationController
        let coveredVisitable = presenter.topViewController as? VisitableViewController

        stackedModalNavigationControllers.append(stackedModal)
        presenter.present(stackedModal, animated: proposal.animated)

        // Sheet presentations don't deliver disappearance callbacks to the presenting
        // controller, so synthesize them — matching what a push delivers — to cache a
        // snapshot of the covered page before the web view moves to the new modal.
        if let coveredVisitable {
            delegate.deactivateVisitable(coveredVisitable, on: .modal)
        }
    }

    private func dismissTopmostStackedModal(animated: Bool) {
        guard let topStackedModal = stackedModalNavigationControllers.last else { return }

        presenter(of: topStackedModal).dismiss(animated: animated)
        stackedModalDidDismiss(topStackedModal)
    }

    /// Dismisses every stacked modal presented above the given navigation controller.
    private func dismissStackedModals(above navController: UINavigationController, animated: Bool) {
        let firstStackedModalAbove: UINavigationController?
        if navController === modalNavigationController {
            firstStackedModalAbove = stackedModalNavigationControllers.first
        } else if let index = stackedModalNavigationControllers.firstIndex(where: { $0 === navController }) {
            firstStackedModalAbove = stackedModalNavigationControllers.indices.contains(index + 1) ? stackedModalNavigationControllers[index + 1] : nil
        } else {
            firstStackedModalAbove = nil
        }
        guard let firstStackedModalAbove else { return }

        // Dismissing from the presenter takes everything above it down as well.
        navController.dismiss(animated: animated)
        stackedModalDidDismiss(firstStackedModalAbove)
    }

    private func presenter(of stackedModal: UINavigationController) -> UINavigationController {
        guard let index = stackedModalNavigationControllers.firstIndex(where: { $0 === stackedModal }), index > 0 else {
            return modalNavigationController
        }

        return stackedModalNavigationControllers[index - 1]
    }

    /// The single bookkeeping point for a dismissed stacked modal, no matter who
    /// initiated the dismissal: this class, an interactive swipe-down, or app code
    /// calling `dismiss(animated:)` directly. Idempotent — the dismissal is both
    /// reported by `HotwireNavigationController.modalDismissalHandler` and invoked
    /// synchronously when this class dismisses a stacked modal itself.
    private func stackedModalDidDismiss(_ dismissedNavigationController: UINavigationController) {
        guard let index = stackedModalNavigationControllers.firstIndex(where: { $0 === dismissedNavigationController }) else {
            return // Already handled, or the whole modal context was dismissed.
        }

        // UIKit dismisses everything presented above the dismissed controller too.
        for stackedModal in stackedModalNavigationControllers[index...] {
            (stackedModal as? HotwireNavigationController)?.modalDismissalHandler = nil
        }
        stackedModalNavigationControllers.removeSubrange(index...)

        // Only reactivate the revealed visitable if its navigation controller is still
        // presented — when the whole modal context is going away there is nothing to reveal.
        let revealed = topmostModalNavigationController
        let revealedIsPresented = if revealed === modalNavigationController {
            navigationController.presentedViewController === modalNavigationController && !modalNavigationController.isBeingDismissed
        } else {
            presenter(of: revealed).presentedViewController === revealed && !revealed.isBeingDismissed
        }

        guard revealedIsPresented,
              let revealedVisitable = revealed.topViewController as? VisitableViewController else { return }

        // Set directly because swipe-down and app-initiated dismissals bypass
        // `HotwireNavigationController.dismiss(animated:completion:)`.
        revealedVisitable.appearReason = .revealedByModalDismiss
        delegate.reactivateVisitable(revealedVisitable, on: .modal)
    }

    /// Finds a navigation controller beneath the topmost stacked modal whose top
    /// visitable matches the proposal — i.e. the proposal navigates back to a screen
    /// covered by stacked modal(s), e.g. via `history.back()` from a stacked modal.
    private func navControllerBeneathTopmostStackedModal(matching proposal: VisitProposal) -> UINavigationController? {
        guard !stackedModalNavigationControllers.isEmpty else { return nil }

        let beneathTopmost = [modalNavigationController] + stackedModalNavigationControllers.dropLast()
        return beneathTopmost.reversed().first { navController in
            guard let visitable = navController.topViewController as? VisitableViewController else { return false }
            return visitable.initialVisitableURL.isSameLocation(as: proposal.url, pathProperties: proposal.properties)
        }
    }

    private func dismissEntireModalContext(animated: Bool) {
        // Pre-clearing makes the per-modal dismissal handlers no-op during the chain
        // collapse, so no covered visitable gets spuriously reactivated.
        clearStackedModals()
        navigationController.dismiss(animated: animated)
    }

    private func clearStackedModals() {
        for stackedModal in stackedModalNavigationControllers {
            (stackedModal as? HotwireNavigationController)?.modalDismissalHandler = nil
        }
        stackedModalNavigationControllers.removeAll()
    }
}
