import UIKit

/// A tab bar controller that manages multiple tabs, each associated with its own `Navigator` instance.
///
/// This controller loads tabs defined by `HotwireTab` and configures each one with its own `Navigator`.
/// The currently selected tab's navigator is exposed via the `activeNavigator` property.
///
/// By default, every tab performs its initial visit when `load(_:)` is called. Pass
/// `lazyLoadTabs: true` in the initializer to defer each tab's initial visit until the
/// first time the user selects it; the initially selected tab still loads right away.
open class HotwireTabBarController: UITabBarController, NavigationHandler {
    /// Creates a tab bar controller.
    ///
    /// - Parameters:
    ///   - navigatorDelegate: An optional delegate for each tab's `Navigator`.
    ///   - lazyLoadTabs: Controls when tab navigators perform their initial visit.
    ///     When `false` (the default), every tab starts immediately when `load(_:)`
    ///     is called. When `true`, only the initially selected tab starts when tabs
    ///     are loaded; each remaining tab starts the first time the user selects it.
    ///     This affects when each tab's content is loaded, not whether the tab's
    ///     navigator is created.
    public init(
        navigatorDelegate: NavigatorDelegate? = nil,
        lazyLoadTabs: Bool = false
    ) {
        self.navigatorDelegate = navigatorDelegate
        self.lazyLoadTabs = lazyLoadTabs
        super.init(nibName: nil, bundle: nil)
        delegate = self
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Use init(navigatorDelegate:lazyLoadTabs:) instead.")
    }

    /// The active navigator corresponding to the currently selected tab.
    ///
    /// - Returns: A `Navigator` instance for the currently selected tab.
    /// - Note: This property will call `fatalError` if there is no tab matching the selected index.
    public var activeNavigator: Navigator {
        let selectedHotwireTab = currentHotwireTab()

        guard let navigator = navigatorsByIdentifier[selectedHotwireTab.id] else {
            fatalError("No navigator associated with tab \(selectedHotwireTab)")
        }

        return navigator
    }

    /// Loads the provided tabs and configures each one with its own navigator.
    ///
    /// - Parameters:
    ///   - tabs: An array of `HotwireTab` instances representing the tabs to be loaded.
    public func load(_ tabs: [HotwireTab]) {
        hotwireTabs = tabs
        setupTabs()

        if lazyLoadTabs {
            activeNavigator.start()
        } else {
            navigatorsByIdentifier.values.forEach { $0.start() }
        }
    }

    /// Returns the navigator associated with the given tab.
    ///
    /// - Parameter tab: The `HotwireTab` whose associated navigator to retrieve.
    /// - Returns: The existing `Navigator` instance for `tab`, or `nil` if the tab is not part of
    ///   the current configuration or the navigators have not been initialized yet (e.g., before `load(_:)`).
    public func navigator(for tab: HotwireTab) -> Navigator? {
        return navigatorsByIdentifier[tab.id]
    }

    // MARK: NavigationHandler

    open func route(_ url: URL, options: VisitOptions?, parameters: [String: Any]?) {
        activeNavigator.route(url, options: options, parameters: parameters)
    }

    open func route(_ proposal: VisitProposal) {
        activeNavigator.route(proposal)
    }

    // MARK: - Private

    private var hotwireTabs: [HotwireTab] = []
    private var navigatorsByIdentifier: [HotwireTab.ID: Navigator] = [:]
    private let navigatorDelegate: NavigatorDelegate?
    private let lazyLoadTabs: Bool

    /// Configures each tab for the appropriate platform API.
    private func setupTabs() {
        navigatorsByIdentifier.removeAll()
        let contexts = hotwireTabs.map { tabContext(for: $0) }

        if #available(iOS 18.0, visionOS 2.0, *) {
            tabs = contexts.map { makeTab(from: $0) }

            if selectedTab == nil, let firstTab = tabs.first {
                selectedTab = firstTab
            }
        } else {
            viewControllers = contexts.map { makeViewController(from: $0) }

            if let viewControllers,
                !viewControllers.indices.contains(selectedIndex) {
                selectedIndex = 0
            }
        }
    }

    private func tabContext(for tab: HotwireTab) -> TabContext {
        let navigator = makeNavigator(for: tab)

        return TabContext(
            tab: tab,
            navigator: navigator,
            viewController: navigator.rootViewController
        )
    }

    private func makeViewController(from context: TabContext) -> UIViewController {
        context.viewController.tabBarItem = context.tab.makeTabBarItem()

        return context.viewController
    }

    @available(iOS 18.0, visionOS 2.0, *)
    private func makeTab(from context: TabContext) -> UITab {
        return context.tab.makeTab(context.viewController)
    }

    private func makeNavigator(for tab: HotwireTab) -> Navigator {
        let navigator = Navigator(
            configuration: .init(
                name: tab.title,
                startLocation: tab.url
            ),
            delegate: navigatorDelegate
        )

        navigatorsByIdentifier[tab.id] = navigator

        return navigator
    }

    func currentHotwireTab() -> HotwireTab {
        if #available(iOS 18.0, visionOS 2.0, *),
           let identifier = selectedTab?.identifier,
           let match = hotwireTabs.first(where: { $0.id == identifier }) {
            return match
        }

        guard hotwireTabs.indices.contains(selectedIndex) else {
            fatalError("No tab matching the selected index")
        }

        return hotwireTabs[selectedIndex]
    }
}

private extension HotwireTabBarController {
    struct TabContext {
        let tab: HotwireTab
        let navigator: Navigator
        let viewController: UIViewController
    }
}

extension HotwireTabBarController: UITabBarControllerDelegate {
    public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        activeNavigator.start()
    }

    @available(iOS 18.0, visionOS 2.0, *)
    public func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        activeNavigator.start()
    }
}
