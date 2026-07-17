# Hotwire Native for iOS

![Swift](https://img.shields.io/badge/Swift-5.3-blue)
![iOS](https://img.shields.io/badge/iOS-14+-green)
![Turbo](https://img.shields.io/badge/Turbo-7+-purple)

[Hotwire Native](https://native.hotwired.dev) is a high-level native framework, available for iOS and Android, that provides you with all the tools you need to leverage your web app and build great mobile apps.

This native Swift library integrates with your [Hotwire](https://hotwired.dev) web app by wrapping it in a native iOS shell. It manages a single WKWebView instance across multiple view controllers, giving you native navigation UI with all the client-side performance benefits of Hotwire.

Read more on [native.hotwired.dev](https://native.hotwired.dev).

## Fork additions

### Stacked modals (`modal_presentation: "stack"`)

A modal-context path rule can opt into presenting as a new modal *on top of* the
currently presented modal — mirroring stacked dialog destinations on Android —
instead of pushing onto the modal navigation stack:

```json
{
  "patterns": ["/select_options"],
  "properties": {
    "context": "modal",
    "modal_presentation": "stack"
  }
}
```

- All stacked modals share the modal session's web view; selections handed back via
  `sessionStorage` + `pageshow` keep working unchanged.
- `modal_style` applies per stacked modal (e.g. `medium` for a half-height sheet).
- Navigating back (`history.back()`) from a stacked modal dismisses it; default-context
  navigation dismisses the entire modal chain.
- When no modal is presented, `stack` behaves like `default`. Servers that omit the
  property get the existing push behavior, so the property is safe to roll out
  independently of app releases.
- Requires `Hotwire.config.defaultNavigationController` to return a
  `HotwireNavigationController` (the default) so interactive and app-initiated
  dismissals are detected.

### Fit-content sheets (`modal_style: "fit"`) and undimmed sheets (`modal_dimming: false`)

`modal_style: "fit"` presents a modal as a sheet with a single custom detent
meant to hug the web content's height:

```json
{
  "patterns": ["^/onboarding$"],
  "properties": {
    "context": "modal",
    "modal_style": "fit",
    "modal_dimming": false
  }
}
```

- The sheet opens at a provisional height (40% of the maximum detent). The web
  page reports its actual content height through a `sheet-size` bridge
  component in the host app, which replaces the detent under the public
  `UISheetPresentationController.Detent.Identifier.fitContent` identifier.
- `modal_dimming: false` removes the dimming view and lets touches outside the
  sheet pass through to the presenting screen (Apple Maps-style). It is
  independent of `modal_style` — an undimmed `medium` sheet works too.
- Custom detents need iOS 16; older systems fall back to a large sheet.
  Unknown `modal_style` values already fall back to `large`, and apps without
  this fork ignore both properties, so servers can ship them ahead of app
  updates.

### Recover web views killed while the app was suspended

iOS reclaims WKWebView WebContent processes from suspended apps; the
terminations are reported while the app is foregrounding, when
`applicationState` is still `.background`. Upstream queues those sessions in
`backgroundTerminatedWebViewSessions` but only drains the queue on
`willEnterForeground` — which has already passed — so the sessions are never
reloaded and their web views stay blank until a manual refresh (WebKit's own
crash auto-reload is disabled whenever the navigation delegate implements
`webViewWebContentProcessDidTerminate`, so nothing else recovers them either).
This fork drains the queue again on `didBecomeActive`.

Terminations are not always reported at all: WebKit can also relaunch a
reclaimed WebContent process silently, leaving a fresh `about:blank` JS
context in which evaluation succeeds while `webView.url` still reports the
original page and the view renders white. Upstream's
`queryWebContentProcessState` treats any successful evaluation as `.active`,
so `inspect()` never recovers those sessions. This fork additionally reports
`.terminated` when the evaluated `location.href` is `about:blank` but
`webView.url` isn't (and no load is in flight).

The silent relaunch can also reset `webView.url` to nil, a shape the JS probe
can't detect at all: evaluation succeeds in the fresh context and there is no
original URL left to compare against. `inspect()` therefore recreates any
session that has visited a page but whose web view reports no URL and no load
in flight, before consulting the probe.

### Web-initiated history restorations propose natively

Upstream, a web-side `history.back()` is handled entirely inside the web view:
Turbo restores the previous page in place while the native screen for the *old*
page stays on top of the stack (a phantom entry). This fork's `turbo.js` adapter
cancels web-initiated restoration visits and forwards them to the native side as
a `restore`-action proposal, so the navigator genuinely pops the pushed screen —
or dismisses stacked modal(s) — down to the screen the web history went back to,
then restores there. Native-initiated visits (including the restore visits the
session issues on pop-back) are unaffected.

## Contributing

Hotwire Native for iOS is open-source software, freely distributable under the terms of an [MIT-style license](LICENSE). The [source code is hosted on GitHub](https://github.com/hotwired/hotwire-native-bridge). Development is sponsored by [37signals](https://37signals.com/).

We welcome contributions in the form of bug reports, pull requests, or thoughtful discussions in the [GitHub issue tracker](https://github.com/hotwired/hotwire-native-bridge/issues).

---------

© 2024 37signals LLC
