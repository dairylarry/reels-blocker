import WebKit

enum WebViewConfiguration {

    static func make() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // Persistent cookie store, so the login survives relaunch and reboot.
        // Nothing in this app may ever clear this (§6.3).
        config.websiteDataStore = .default()

        // Default is false on iPhone. Without it, every DM video hijacks the
        // screen into the fullscreen player instead of playing in the thread.
        config.allowsInlineMediaPlayback = true

        // Tap to play. Nothing autoplays — not feed video, not DM video.
        // Decision #10: the project is about not being fed video passively.
        config.mediaTypesRequiringUserActionForPlayback = .all

        config.suppressesIncrementalRendering = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // WKWebView's default UA omits the Safari token, which can get a
        // degraded page served. Append rather than replacing the whole UA so
        // the real OS and WebKit versions stay accurate.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        // NOTE: do not add WKAppBoundDomains to Info.plist. Opting in blocks
        // evaluateJavaScript on non-app-bound domains, which would disable the
        // entire blocking layer in M2 (§6.3).

        return config
    }
}
