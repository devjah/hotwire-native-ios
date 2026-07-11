import UIKit

#if !os(visionOS)
@available(iOS 16.0, *)
public extension UISheetPresentationController.Detent.Identifier {
    /// The content-sized detent created by `modal_style: "fit"`. Bridge
    /// components resize the sheet by replacing the detent under this
    /// identifier with one resolving to the web content's reported height.
    static let fitContent = UISheetPresentationController.Detent.Identifier("fitContent")
}
#endif

extension UINavigationController {
    func replaceLastViewController(with viewController: UIViewController) {
        if Hotwire.config.animateReplaceActions {
            addFadeTransition()
        }

        let viewControllers = viewControllers.dropLast()
        setViewControllers(viewControllers + [viewController], animated: false)
    }

    func setModalPresentationStyle(via proposal: VisitProposal) {
        switch proposal.modalStyle {
        case .medium:
            modalPresentationStyle = .automatic
            #if !os(visionOS)
            if #available(iOS 15.0, *) {
                if let sheet = sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                }
            }
            #endif
        case .large:
            modalPresentationStyle = .automatic
        case .full:
            modalPresentationStyle = .fullScreen
        case .pageSheet:
            modalPresentationStyle = .pageSheet
        case .formSheet:
            modalPresentationStyle = .formSheet
        case .fit:
            // Sized to the web content once a `sheet-size` bridge component
            // reports its height; a provisional height until then. Kept below
            // typical content height so the sheet grows into place — growing
            // reads as loading, shrinking reads as a glitch. Requires custom
            // detents (iOS 16); older systems fall back to a large sheet.
            modalPresentationStyle = .automatic
            #if !os(visionOS)
            if #available(iOS 16.0, *) {
                if let sheet = sheetPresentationController {
                    sheet.detents = [.custom(identifier: .fitContent) { context in
                        context.maximumDetentValue * 0.2
                    }]
                }
            }
            #endif
        }

        #if !os(visionOS)
        if !proposal.modalDimming, #available(iOS 16.0, *) {
            if let sheet = sheetPresentationController {
                sheet.largestUndimmedDetentIdentifier = sheet.detents.last?.identifier
            }
        }
        #endif
    }

    private func addFadeTransition() {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = CATransaction.animationDuration()
        view.layer.add(transition, forKey: kCATransition)
    }
}
