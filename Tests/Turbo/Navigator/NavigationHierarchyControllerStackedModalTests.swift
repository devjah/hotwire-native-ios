@testable import HotwireNative
import XCTest

/// Tests for stacked modals: modal-context proposals carrying
/// `modal_presentation: "stack"` present on top of the current modal instead of
/// pushing onto its navigation stack.
///
/// Tests are written in the same
/// `test_currentContext_givenContext_givenPresentation_modifiers_result()`
/// format as `NavigationHierarchyControllerTests`.
final class NavigationHierarchyControllerStackedModalTests: XCTestCase {
    override func setUp() {
        originalNavigationControllerFactory = Hotwire.config.defaultNavigationController
        Hotwire.config.defaultNavigationController = { TestableNavigationController() }

        navigationController = TestableNavigationController()
        modalNavigationController = TestableNavigationController()

        navigator = Navigator(
            session: session,
            modalSession: modalSession,
            configuration: .init(name: "Test", startLocation: oneURL)
        )
        hierarchyController = NavigationHierarchyController(delegate: navigator, navigationController: navigationController, modalNavigationController: modalNavigationController)
        navigator.hierarchyController = hierarchyController

        loadNavigationControllerInWindow()
    }

    override func tearDown() {
        Hotwire.config.defaultNavigationController = originalNavigationControllerFactory
    }

    // MARK: Presenting

    func test_modal_modal_default_stack_presentsModalOnTopOfModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        XCTAssertEqual(modalNavigationController.viewControllers.count, 1)

        let proposal = stackedProposal(path: "/two")
        navigator.route(proposal)

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertIdentical(modalNavigationController.presentedViewController, topStackedModal)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
        XCTAssert(topStackedModal?.viewControllers.last is VisitableViewController)
        XCTAssertEqual(modalNavigationController.viewControllers.count, 1)
        assertVisited(url: proposal.url, on: .modal)

        XCTAssertIdentical(navigator.activeNavigationController, topStackedModal)
        XCTAssertIdentical(navigator.topmostModalNavigationController, topStackedModal)
        XCTAssertIdentical(navigator.modalRootViewController, modalNavigationController)
    }

    func test_default_modal_default_stack_noModalPresented_presentsRootModal() {
        navigationController.pushViewController(UIViewController(), animated: false)

        navigator.route(stackedProposal(path: "/one"))

        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigator.topmostModalNavigationController, modalNavigationController)
    }

    func test_modal_modal_default_stack_onTopOfStackedModal_presentsSecondStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        navigator.route(stackedProposal(path: "/three"))

        XCTAssertEqual(stackedModals.count, 2)
        XCTAssertIdentical(stackedModals[0].presentedViewController, stackedModals[1])
        XCTAssertIdentical(navigator.topmostModalNavigationController, stackedModals[1])
        assertVisited(url: threeURL, on: .modal)
    }

    func test_modal_modal_default_whileStackedModalPresented_pushesOnTopmostStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(path: "/three", context: .modal))

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 2)
        XCTAssertEqual(modalNavigationController.viewControllers.count, 1)
        assertVisited(url: threeURL, on: .modal)
    }

    func test_modal_modal_default_stack_visitingSamePage_replacesOnTopmostStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        let originalTop = topStackedModal?.topViewController

        navigator.route(stackedProposal(path: "/two"))

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
        XCTAssertNotIdentical(topStackedModal?.topViewController, originalTop)
        assertVisited(url: twoURL, on: .modal)
    }

    // MARK: Navigating back beneath stacked modals

    func test_modal_modal_default_visitingPageBeneathStackedModal_dismissesStackedModalAndRestoresCoveredVisitable() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        let coveredViewController = modalNavigationController.topViewController as! VisitableViewController

        navigator.route(stackedProposal(path: "/two"))
        assertVisited(url: twoURL, on: .modal)

        // E.g. `history.back()` from the stacked modal.
        navigator.route(VisitProposal(path: "/one", context: .modal))

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
        XCTAssertNil(modalNavigationController.presentedViewController)
        XCTAssertIdentical(modalNavigationController.topViewController, coveredViewController)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, coveredViewController)
        XCTAssertEqual(coveredViewController.appearReason, .revealedByModalDismiss)
    }

    func test_modal_modal_default_visitingPageBeneathTwoStackedModals_dismissesBothStackedModals() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        let coveredViewController = modalNavigationController.topViewController as! VisitableViewController

        navigator.route(stackedProposal(path: "/two"))
        navigator.route(stackedProposal(path: "/three"))
        XCTAssertEqual(stackedModals.count, 2)

        navigator.route(VisitProposal(path: "/one", context: .modal))

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, coveredViewController)
    }

    func test_modal_modal_default_visitingPreviousPageWithinStackedModal_popsWithinStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        navigator.route(VisitProposal(path: "/three", context: .modal))
        XCTAssertEqual(topStackedModal?.viewControllers.count, 2)

        navigator.route(VisitProposal(path: "/two", context: .modal))

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
        assertVisited(url: twoURL, on: .modal)
    }

    func test_modal_modal_default_visitingPreviousStackTaggedPageWithinStackedModal_popsInsteadOfStackingDuplicate() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        navigator.route(VisitProposal(path: "/three", context: .modal))
        XCTAssertEqual(topStackedModal?.viewControllers.count, 2)

        // E.g. `history.back()` from a screen pushed inside the sheet to the
        // sheet's root, whose path rule is itself stack-tagged: must pop within
        // the sheet, not present a duplicate sheet on top.
        navigator.route(stackedProposal(path: "/two"))

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
        assertVisited(url: twoURL, on: .modal)
    }

    // MARK: Pop

    func test_modal_any_pop_stackedModalWithMultipleViewControllers_popsWithinStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        navigator.route(VisitProposal(path: "/three", context: .modal))

        navigator.route(VisitProposal(presentation: .pop))

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
    }

    func test_modal_any_pop_stackedModalWithOneViewController_dismissesStackedModalOnly() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        let coveredViewController = modalNavigationController.topViewController as! VisitableViewController
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(presentation: .pop))

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, coveredViewController)
    }

    func test_modal_any_pop_afterStackedModalDismissed_dismissesRootModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(presentation: .pop))
        navigator.route(VisitProposal(presentation: .pop))

        XCTAssertNil(navigationController.presentedViewController)
    }

    func test_navigatorPop_dismissesTopmostStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        navigator.pop()

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
    }

    // MARK: Dismissing the entire modal context

    func test_modal_default_default_whileStackedModalPresented_dismissesEntireChainAndPushesOnMain() {
        navigator.route(VisitProposal(path: "/one"))
        navigator.route(VisitProposal(path: "/two", context: .modal))
        navigator.route(stackedProposal(path: "/three"))
        let stackedVisitable = navigator.modalSession.activeVisitable

        let proposal = VisitProposal(path: "/four")
        navigator.route(proposal)

        XCTAssertNil(navigationController.presentedViewController)
        XCTAssert(stackedModals.isEmpty)
        XCTAssertEqual(navigationController.viewControllers.count, 2)
        assertVisited(url: proposal.url, on: .main)

        // No spurious reactivation of the covered modal visitable during the chain collapse.
        XCTAssertIdentical(navigator.modalSession.activeVisitable, stackedVisitable)
    }

    func test_modal_historical_whileStackedModalPresented_dismissesEntireChain() {
        navigator.route(VisitProposal(path: "/one"))
        navigator.route(VisitProposal(path: "/two", context: .modal))
        navigator.route(stackedProposal(path: "/three"))

        let recedeProposal = VisitProposal(
            path: PathRule.recedeHistoricalLocation.patterns.first!,
            additionalProperties: PathRule.recedeHistoricalLocation.properties
        )
        navigator.route(recedeProposal)

        XCTAssertNil(navigationController.presentedViewController)
        XCTAssert(stackedModals.isEmpty)
    }

    func test_any_any_clearAll_whileStackedModalPresented_dismissesChainAndPopsToRoot() {
        let rootController = UIViewController()
        navigationController.viewControllers = [rootController, UIViewController()]
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(presentation: .clearAll))

        XCTAssertNil(navigationController.presentedViewController)
        XCTAssert(stackedModals.isEmpty)
        XCTAssertEqual(navigationController.viewControllers, [rootController])
    }

    func test_any_any_replaceRoot_whileStackedModalPresented_dismissesChainAndReplacesRoot() {
        navigationController.viewControllers = [UIViewController(), UIViewController()]
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(presentation: .replaceRoot))

        XCTAssertNil(navigationController.presentedViewController)
        XCTAssert(stackedModals.isEmpty)
        XCTAssertEqual(navigationController.viewControllers.count, 1)
    }

    // MARK: Refresh

    func test_modal_modal_refresh_stackedModalWithOneViewController_dismissesStackedModalAndRestoresCoveredVisitable() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        let coveredViewController = modalNavigationController.topViewController as! VisitableViewController
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(context: .modal, presentation: .refresh))

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, coveredViewController)
    }

    func test_modal_modal_refresh_stackedModalWithMultipleViewControllers_popsWithinStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        navigator.route(VisitProposal(path: "/three", context: .modal))

        navigator.route(VisitProposal(context: .modal, presentation: .refresh))

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
        XCTAssertEqual(navigator.modalSession.activeVisitable?.initialVisitableURL, twoURL)
    }

    // MARK: Replace

    func test_modal_modal_replace_whileStackedModalPresented_replacesOnTopmostStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        let proposal = VisitProposal(path: "/three", context: .modal, presentation: .replace)
        navigator.route(proposal)

        XCTAssertEqual(stackedModals.count, 1)
        XCTAssertEqual(topStackedModal?.viewControllers.count, 1)
        XCTAssertEqual(modalNavigationController.viewControllers.count, 1)
        assertVisited(url: proposal.url, on: .modal)
    }

    // MARK: Dismissals outside the hierarchy controller's control

    func test_interactiveDismissal_ofStackedModal_restoresCoveredVisitable() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        let coveredViewController = modalNavigationController.topViewController as! VisitableViewController
        navigator.route(stackedProposal(path: "/two"))
        let stackedModal = topStackedModal as! HotwireNavigationController

        // Simulate a completed swipe-down: UIKit clears the presentation, then the
        // dismissed controller's `viewDidDisappear` fires the handler.
        modalNavigationController.presentedViewController = nil
        stackedModal.modalDismissalHandler?()

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, coveredViewController)
        XCTAssertEqual(coveredViewController.appearReason, .revealedByModalDismiss)
    }

    func test_appInitiatedDismissal_ofStackedModal_restoresCoveredVisitable() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        let coveredViewController = modalNavigationController.topViewController as! VisitableViewController
        navigator.route(stackedProposal(path: "/two"))

        // E.g. a bridge component calling `dismiss(animated:)` directly; UIKit forwards
        // the call to the presenting controller.
        modalNavigationController.dismiss(animated: false)

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigationController.presentedViewController, modalNavigationController)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, coveredViewController)
    }

    func test_stackedModalDismissalHandler_afterChainCollapse_isNoOp() {
        navigator.route(VisitProposal(path: "/one"))
        navigator.route(VisitProposal(path: "/two", context: .modal))
        navigator.route(stackedProposal(path: "/three"))
        let stackedModal = topStackedModal as! HotwireNavigationController
        let handler = stackedModal.modalDismissalHandler

        navigator.route(VisitProposal(path: "/four"))
        XCTAssert(stackedModals.isEmpty)
        XCTAssertNil(stackedModal.modalDismissalHandler)

        // A late lifecycle callback for the already-handled modal must not corrupt state.
        let activeVisitable = navigator.modalSession.activeVisitable
        handler?()
        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigator.modalSession.activeVisitable, activeVisitable)
    }

    func test_rootModalDismissal_clearsStackedModalState() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))
        XCTAssertEqual(stackedModals.count, 1)

        // E.g. app code dismissing the whole modal context from the main stack.
        navigationController.dismiss(animated: false)

        XCTAssert(stackedModals.isEmpty)
        XCTAssertIdentical(navigator.topmostModalNavigationController, modalNavigationController)
    }

    // MARK: Modal properties on stacked modals

    func test_modalStyle_isAppliedToStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two", additionalProperties: ["modal_style": "form_sheet"]))

        XCTAssertEqual(topStackedModal?.modalPresentationStyle, .formSheet)
    }

    func test_modalDismissGestureDisabled_isAppliedToStackedModal() {
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two", additionalProperties: ["modal_dismiss_gesture_enabled": false]))

        XCTAssertEqual(topStackedModal?.topViewController?.isModalInPresentation, true)
    }

    // MARK: Alerts

    func test_presentingUIAlertController_whileStackedModalPresented_presentsOnTopmostStackedModal() {
        navigator.delegate = alertControllerDelegate
        navigator.route(VisitProposal(path: "/one", context: .modal))
        navigator.route(stackedProposal(path: "/two"))

        navigator.route(VisitProposal(path: "/alert"))

        XCTAssert(topStackedModal?.presentedViewController is UIAlertController)
        XCTAssertFalse(modalNavigationController.presentedViewController is UIAlertController)
    }

    // MARK: Private

    private enum Context {
        case main, modal
    }

    private let baseURL = URL(string: "https://example.com")!
    private lazy var oneURL = baseURL.appendingPathComponent("/one")
    private lazy var twoURL = baseURL.appendingPathComponent("/two")
    private lazy var threeURL = baseURL.appendingPathComponent("/three")

    private let session = Session(webView: Hotwire.config.makeWebView())
    private let modalSession = Session(webView: Hotwire.config.makeWebView())

    private var navigator: Navigator!
    private let alertControllerDelegate = StackedModalAlertControllerDelegate()
    private var hierarchyController: NavigationHierarchyController!
    private var navigationController: TestableNavigationController!
    private var modalNavigationController: TestableNavigationController!
    private var originalNavigationControllerFactory: (() -> UINavigationController)!

    private let window = UIWindow()

    private var stackedModals: [UINavigationController] {
        hierarchyController.stackedModalNavigationControllers
    }

    private var topStackedModal: UINavigationController? {
        stackedModals.last
    }

    private func stackedProposal(path: String, additionalProperties: [String: AnyHashable] = [:]) -> VisitProposal {
        var properties: [String: AnyHashable] = ["modal_presentation": "stack"]
        properties.merge(additionalProperties) { _, new in new }
        return VisitProposal(path: path, context: .modal, additionalProperties: properties)
    }

    // Simulate a "real" app so presenting view controllers works under test.
    private func loadNavigationControllerInWindow() {
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        navigationController.loadViewIfNeeded()
    }

    private func assertVisited(url: URL, on context: Context) {
        switch context {
        case .main:
            XCTAssertEqual(navigator.session.activeVisitable?.initialVisitableURL, url)
        case .modal:
            XCTAssertEqual(navigator.modalSession.activeVisitable?.initialVisitableURL, url)
        }
    }
}

// MARK: - StackedModalAlertControllerDelegate

private class StackedModalAlertControllerDelegate: NavigatorDelegate {
    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        if proposal.url.path == "/alert" {
            return .acceptCustom(UIAlertController(title: "Alert", message: nil, preferredStyle: .alert))
        }

        return .accept
    }
}
