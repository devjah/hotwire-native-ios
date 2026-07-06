import Foundation
import WebKit

/// An interface to implement to provide custom
/// route decision handling behaviors in your app.
public protocol RouteDecisionHandler {
    /// The decision handler name used in debug logging.
    var name: String { get }

    /// Determines whether the proposed visit matches this decision handler.
    /// Use your own custom rules based on the visit's location domain, protocol, path,
    /// options, path properties, or any other factors.
    /// - Parameters:
    ///     - proposal: The proposed visit, including its location, options, and path properties.
    ///     - configuration: The configuration of the navigator where the navigation is taking place.
    /// - Returns: `true` if the proposed visit matches this decision handler, `false` otherwise.
    func matches(proposal: VisitProposal,
                 configuration: Navigator.Configuration) -> Bool

    /// Handle custom routing behavior when a match is found.
    /// For example, open an external browser or app for external domain urls.
    /// - Parameters:
    ///     - proposal: The proposed visit, including its location, options, and path properties.
    ///     - configuration: The configuration of the navigator where the navigation is taking place.
    ///     - navigator: The navigator instance responsible for the navigation.
    func handle(proposal: VisitProposal,
                configuration: Navigator.Configuration,
                navigator: Navigating) -> Router.Decision
}
