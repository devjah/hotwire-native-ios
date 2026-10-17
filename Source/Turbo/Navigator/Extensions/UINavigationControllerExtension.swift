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

    /// One modal navigation controller presents every modal visit, and its
    /// sheet presentation controller outlives a dismissal: the detents the last
    /// sheet set, the detent it was dragged to and its undimmed detent are all
    /// still there when the next one is presented. So every sheet style sets
    /// each of them, and a sheet opens at its own size whatever came before it —
    /// a `large` sheet after a `medium` one is not a half sheet, and a `medium`
    /// sheet dragged to full height opens at half the next time.
    func setModalPresentationStyle(via proposal: VisitProposal) {
        switch proposal.modalStyle {
        case .medium:
            modalPresentationStyle = .automatic
            #if !os(visionOS)
            if #available(iOS 15.0, *) {
                setSheetDetents([.medium(), .large()], selected: .medium)
            }
            #endif
        case .large:
            modalPresentationStyle = .automatic
            resetSheetDetents()
        case .full:
            modalPresentationStyle = .fullScreen
        case .overFullScreen:
            // Same size as .fullScreen, but the presenter's view stays in the
            // window hierarchy behind it — the page underneath keeps running.
            modalPresentationStyle = .overFullScreen
        case .pageSheet:
            modalPresentationStyle = .pageSheet
            resetSheetDetents()
        case .formSheet:
            modalPresentationStyle = .formSheet
            resetSheetDetents()
        case .fit:
            // Sized to the web content once a `sheet-size` bridge component
            // reports its height; a provisional height until then. Kept below
            // typical content height so the sheet grows into place — growing
            // reads as loading, shrinking reads as a glitch. Requires custom
            // detents (iOS 16); older systems fall back to a large sheet.
            modalPresentationStyle = .automatic
            #if !os(visionOS)
            if #available(iOS 16.0, *) {
                setSheetDetents([.custom(identifier: .fitContent) { context in
                    context.maximumDetentValue * 0.2
                }], selected: .fitContent)
            } else {
                resetSheetDetents()
            }
            #endif
        }

        #if !os(visionOS)
        if #available(iOS 16.0, *) {
            if let sheet = sheetPresentationController {
                sheet.largestUndimmedDetentIdentifier = proposal.modalDimming ? nil : sheet.detents.last?.identifier
            }
        }
        #endif
    }

    /// UIKit's own sheet: one full-height detent.
    private func resetSheetDetents() {
        #if !os(visionOS)
        if #available(iOS 15.0, *) {
            setSheetDetents([.large()], selected: .large)
        }
        #endif
    }

    #if !os(visionOS)
    @available(iOS 15.0, *)
    private func setSheetDetents(_ detents: [UISheetPresentationController.Detent],
                                 selected: UISheetPresentationController.Detent.Identifier) {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = detents
        sheet.selectedDetentIdentifier = selected
    }
    #endif

    private func addFadeTransition() {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = CATransaction.animationDuration()
        view.layer.add(transition, forKey: kCATransition)
    }
}
