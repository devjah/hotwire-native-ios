import Foundation

public final class AppNavigationRouteDecisionHandler: RouteDecisionHandler {
    public let name: String = "app-navigation"

    public init() {}

    public func matches(proposal: VisitProposal,
                        configuration: Navigator.Configuration) -> Bool {
        let location = proposal.url
        if #available(iOS 16, *) {
            return configuration.startLocation.host() == location.host()
        }

        return configuration.startLocation.host == location.host
    }

    public func handle(proposal: VisitProposal,
                       configuration: Navigator.Configuration,
                       navigator: Navigating) -> Router.Decision {
        logger.info("Routing \(proposal.url.absoluteString)")
        return .navigate
    }
}
