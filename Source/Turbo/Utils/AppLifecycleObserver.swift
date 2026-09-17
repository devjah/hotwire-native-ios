import Foundation
import UIKit

protocol AppLifecycleObserverDelegate: AnyObject {
    func appDidEnterBackground()
    func appWillEnterForeground()
    func appDidBecomeActive()
}

final class AppLifecycleObserver {
    weak var delegate: AppLifecycleObserverDelegate?

    var appState: UIApplication.State {
        stateProvider()
    }

    /// Where `appState` comes from. `UIApplication.shared.applicationState` in
    /// the app; a test injects the state it wants to pose, because the three
    /// states this class reports on are precisely what a unit test cannot
    /// produce — a test host is `.active` for its whole life.
    private let stateProvider: () -> UIApplication.State

    init(delegate: AppLifecycleObserverDelegate? = nil,
         stateProvider: @escaping () -> UIApplication.State = { UIApplication.shared.applicationState }) {
        self.delegate = delegate
        self.stateProvider = stateProvider

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        delegate?.appDidEnterBackground()
    }

    @objc private func appWillEnterForeground() {
        delegate?.appWillEnterForeground()
    }

    @objc private func appDidBecomeActive() {
        delegate?.appDidBecomeActive()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
