import SafariServices
import WebKit

protocol NavigationHierarchyControllerDelegate: AnyObject {
    
    /// Once the navigation hierarchy is modified, begin a visit on a navigation controller.
    ///
    /// - Parameters:
    ///   - _: the Visitable destination
    ///   - on: the navigation controller that was modified
    ///   - with: the visit options
    func visit(_ : Visitable,
               on: NavigationHierarchyController.NavigationStackType,
               with: VisitOptions)
    
    /// A refresh will pop (or dismiss) then ask the session to refresh the previous (or underlying) Visitable.
    ///
    /// - Parameters:
    ///   - navigationStack: the stack where the refresh is happening
    ///   - newTopmostVisitable: the visitable to be refreshed
    func refreshVisitable(navigationStack: NavigationHierarchyController.NavigationStackType,
                          newTopmostVisitable: Visitable)

    /// Restores a visitable revealed by dismissing a stacked modal. Sheet presentations
    /// don't deliver UIKit appearance callbacks to the presenting controller, so the
    /// session issues a `.restore` visit directly, re-attaching the web view — the same
    /// thing a refresh does. No-op if the visitable already owns the web view.
    ///
    /// - Parameters:
    ///   - _: the visitable being revealed
    ///   - on: the stack the visitable belongs to
    func reactivateVisitable(_ : Visitable,
                             on: NavigationHierarchyController.NavigationStackType)

    /// Synthesizes the disappearance lifecycle for a visitable covered by a stacked
    /// modal, mirroring what a push delivers, so the session caches a snapshot and
    /// records the previous visit before the web view moves to the new modal.
    ///
    /// - Parameters:
    ///   - _: the visitable being covered
    ///   - on: the stack the visitable belongs to
    func deactivateVisitable(_ : Visitable,
                             on: NavigationHierarchyController.NavigationStackType)
}
