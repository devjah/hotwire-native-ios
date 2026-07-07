public extension PathProperties {
    var context: Navigation.Context {
        guard let rawValue = self["context"] as? String,
              let context = Navigation.Context(rawValue: rawValue) else {
            return .default
        }

        return context
    }

    var presentation: Navigation.Presentation {
        guard let rawValue = self["presentation"] as? String,
              let presentation = Navigation.Presentation(rawValue: rawValue) else {
            return .default
        }

        return presentation
    }

    var modalStyle: Navigation.ModalStyle {
        guard let rawValue = self["modal_style"] as? String,
              let modalStyle = Navigation.ModalStyle(rawValue: rawValue) else {
            return .large
        }

        return modalStyle
    }

    /// Determines how a modal-context visit is presented while another modal is
    /// already on screen.
    ///
    /// - `default`: pushes onto the current modal navigation stack (existing behavior).
    /// - `stack`: presents the destination as a new modal on top of the current one,
    ///   mirroring stacked dialog destinations on Android.
    ///
    /// ```json
    /// {
    ///   "rules": [
    ///     {
    ///       "patterns": ["/select_options"],
    ///       "properties": {
    ///         "context": "modal",
    ///         "modal_presentation": "stack"
    ///       }
    ///     }
    ///   ]
    /// }
    /// ```
    ///
    /// - Note: When no modal is presented, `stack` behaves exactly like `default`.
    var modalPresentation: Navigation.ModalPresentation {
        guard let rawValue = self["modal_presentation"] as? String,
              let modalPresentation = Navigation.ModalPresentation(rawValue: rawValue) else {
            return .default
        }

        return modalPresentation
    }

    var pullToRefreshEnabled: Bool {
        self["pull_to_refresh_enabled"] as? Bool ?? true
    }

    /// Whether a sheet-presented modal dims the screen behind it.
    ///
    /// Set `"modal_dimming": false` on a modal rule to remove the dimming view
    /// and let touches outside the sheet pass through to the presenting screen
    /// (Apple Maps-style). Combines with any sheet `modal_style`, e.g. `"fit"`
    /// or `"medium"`.
    var modalDimming: Bool {
        self["modal_dimming"] as? Bool ?? true
    }

    var modalDismissGestureEnabled: Bool {
        self["modal_dismiss_gesture_enabled"] as? Bool ?? true
    }

    /// Used to identify a custom native view controller if provided in the path configuration properties of a given pattern.
    ///
    /// For example, given the following configuration file:
    ///
    /// ```json
    /// {
    ///   "rules": [
    ///     {
    ///       "patterns": [
    ///         "/recipes/*"
    ///       ],
    ///       "properties": {
    ///         "view_controller": "recipes",
    ///       }
    ///     }
    ///  ]
    /// }
    /// ```
    ///
    /// A VisitProposal to `https://example.com/recipes/` will have
    /// ```swift
    /// proposal.viewController == "recipes"
    /// ```
    ///
    /// - Important: A default value is provided in case the view controller property is missing from the configuration file. This will route the default `VisitableViewController`.
    /// - Note: A `ViewController` must conform to `PathConfigurationIdentifiable` to couple the identifier with a view controlelr.
    var viewController: String {
        guard let viewController = self["view_controller"] as? String else {
            return VisitableViewController.pathConfigurationIdentifier
        }

        return viewController
    }

    /// Allows the proposal to change the animation status when pushing, popping or presenting.
    var animated: Bool {
        self["animated"] as? Bool ?? true
    }

    internal var historicalLocation: Bool {
        self["historical_location"] as? Bool ?? false
    }

    var queryStringPresentation: Navigation.QueryStringPresentation {
        guard let rawValue = self["query_string_presentation"] as? String,
              let presentation = Navigation.QueryStringPresentation(rawValue: rawValue) else {
            return .default
        }

        return presentation
    }
}
