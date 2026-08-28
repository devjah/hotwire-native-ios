public enum Navigation {
    public enum Context: String {
        case `default`
        case modal
    }

    public enum Presentation: String {
        case `default`
        case pop
        case replace
        case refresh
        case clearAll = "clear_all"
        case replaceRoot = "replace_root"
        case none
    }

    public enum ModalStyle: String {
        case medium
        case large
        case full
        case pageSheet = "page_sheet"
        case formSheet = "form_sheet"
        case fit
        /// Covers the screen without removing the presenting view controller's
        /// view from the window hierarchy — the presenting web view stays
        /// loaded, keeps its WebSocket, and goes on rendering. Use for a screen
        /// you expect to return from constantly, where the page underneath is
        /// live (a dashboard fed by broadcasts) and a reload on the way back
        /// would show stale content or cost a request.
        ///
        /// UIKit does not offer swipe-to-dismiss for this style: give the
        /// presented screen its own dismiss control.
        case overFullScreen = "over_full_screen"
    }

    public enum ModalPresentation: String {
        case `default`
        case stack
    }
}
