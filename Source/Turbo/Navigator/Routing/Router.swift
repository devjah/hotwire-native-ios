import Foundation

/// Routes location urls within in-app navigation or with custom behaviors
/// provided in `RouteDecisionHandler` instances.
public final class Router {
    let decisionHandlers: [RouteDecisionHandler]

    init(decisionHandlers: [RouteDecisionHandler]) {
        self.decisionHandlers = decisionHandlers
    }

    func decideRoute(for proposal: VisitProposal,
                     configuration: Navigator.Configuration,
                     navigator: Navigating) -> Router.Decision {
        for handler in decisionHandlers {
            if handler.matches(proposal: proposal, configuration: configuration) {
                logger.debug("[Router] handler match found handler: \(handler.name) proposal: \(proposal)")
                return handler.handle(proposal: proposal,
                               configuration: configuration,
                               navigator: navigator)
            }
        }

        logger.warning("[Router] no handler for proposal: \(proposal)")
        return .cancel
    }
}

public extension Router {
    enum Decision {
        // Permit in-app navigation with your app's domain urls.
        case navigate
        // Prevent in-app navigation. Always use this for external domain urls.
        case cancel
    }
}
