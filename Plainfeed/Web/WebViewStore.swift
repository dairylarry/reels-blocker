import SwiftUI
import WebKit

/// Owns the single WKWebView for the app's lifetime.
///
/// One web view, not one per tab (§6.5) — tab switching is navigation, so the
/// login, the cookie jar, and the back stack are shared. SwiftUI redraws must
/// never recreate it, hence a reference type held by the App.
@MainActor
final class WebViewStore: NSObject, ObservableObject {

    let webView: WKWebView

    let diagnostics = DiagnosticsStore()

    /// Set by the Diagnostics button in the banner; ContentView presents it.
    @Published var showDiagnostics = false

    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var currentURL: URL?

    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WebViewConfiguration.make()
        config.userContentController.addUserScript(BlockingScript.userScript())
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        // NOTE: WKWebView COPIES its configuration on init, so registering the
        // handler on `config` here would never reach the web view and
        // assertions would silently never arrive. Register on the view's own
        // copy instead.
        webView.configuration.userContentController.add(self, name: BlockingScript.messageHandler)

        webView.allowsBackForwardNavigationGestures = true   // edge-swipe back

        // Required for Safari Web Inspector to see this view at all. Since
        // iOS 16.4 a WKWebView is NOT inspectable by default, and this is a
        // personal app whose whole maintenance story is "attach the inspector
        // and fix the selector", so it stays on in release builds too.
        webView.isInspectable = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // Let the page paint its own background rather than flashing white.
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground

        attachRefreshControl()
        observe()
    }

    func loadStart() {
        guard webView.url == nil else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let signedIn = cookies.contains {
                $0.name == Site.sessionCookieName && $0.domain.contains("instagram.com")
            }
            Task { @MainActor in
                guard let self, self.webView.url == nil else { return }
                self.webView.load(URLRequest(url: signedIn ? Site.start : Site.signedOutStart))
            }
        }
    }

    func go(to tab: Site.Tab) {
        webView.load(URLRequest(url: tab.url))
    }

    // MARK: - Diagnostics

    private func noteRoute(_ url: URL?) {
        diagnostics.currentURL = url
        guard let url else { diagnostics.currentRoute = "—"; return }
        // Show what the rules DID, not just how the path classified —
        // "other" alone reads like a bug on the home feed.
        let route = Rules.classify(url)
        let decision = Rules.decide(destination: url, source: webView.url)
        diagnostics.currentRoute = "\(route) · \(decision == .allow ? "allowed" : "blocked")"
    }

    // MARK: - Pull to refresh

    private func attachRefreshControl() {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = rc
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        webView.reload()
    }

    // MARK: - State

    private func observe() {
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.isLoading = wv.isLoading
                    if !wv.isLoading { wv.scrollView.refreshControl?.endRefreshing() }
                }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.currentURL = wv.url
                    self?.noteRoute(wv.url)
                }
            },
        ]
    }
}

// MARK: - Navigation

extension WebViewStore: WKNavigationDelegate {

    /// M1 keeps this deliberately permissive — no blocking yet, so the baseline
    /// can be judged on its own (milestone M1). The route matrix (§4.1) and the
    /// reel containment rules (§2.1) land here in M2.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }

        // Custom schemes (instagram://, fb://) would fail to load and can be
        // emitted by "open in app" banners. Swallow them.
        if let scheme = url.scheme?.lowercased(), scheme != "https", scheme != "http" {
            return .cancel
        }

        // The source page is what makes the one-hop reel rule work: a reel
        // opened from a DM plays, a reel opened from another reel does not.
        let source = navigationAction.sourceFrame.request.url ?? webView.url

        if Rules.isUnknownReelShape(url) {
            diagnostics.log("R2", "unknown /reels/ shape allowed: \(url.path)")
        }

        switch Rules.decide(destination: url, source: source) {
        case .allow:
            return .allow
        case .blockToHome:
            if webView.url == nil {
                webView.load(URLRequest(url: Rules.home))
            }
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
        #if DEBUG
        webView.evaluateJavaScript("navigator.userAgent") { ua, _ in
            guard let ua = ua as? String else { return }
            let url = URL.documentsDirectory.appendingPathComponent("ua.txt")
            try? ua.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        webView.scrollView.refreshControl?.endRefreshing()
    }
}

// MARK: - UI delegate

extension WebViewStore: WKUIDelegate {

    /// Voice notes call getUserMedia. Without this the web view denies capture
    /// by default and recording silently fails; iOS still gates the hardware
    /// behind its own permission prompt, so this grants the *page* access, not
    /// the app.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(origin.host.hasSuffix("instagram.com") ? .grant : .deny)
    }

    /// Returning nil here makes every target="_blank" link silently dead —
    /// which on Instagram includes most outbound links in bios and DMs. Load it
    /// in the same view instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - Assertion results from the injected script

extension WebViewStore: WKScriptMessageHandler {

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == BlockingScript.messageHandler,
              let body = message.body as? [String: Any]
        else { return }

        // Events reported by a rule about itself — e.g. R7's over-match guard.
        if let events = body["events"] as? [[String: Any]] {
            for e in events {
                guard let source = e["source"] as? String,
                      let message = e["message"] as? String else { continue }
                diagnostics.log(source, message)
            }
        }

        guard let raw = body["assertions"] as? [[String: Any]] else { return }

        let now = Date()
        let results: [AssertionResult] = raw.compactMap { entry in
            guard let rule = entry["rule"] as? String,
                  let name = entry["name"] as? String,
                  let status = entry["status"] as? String,
                  let parsed = AssertionResult.Status(rawValue: status)
            else { return nil }
            return AssertionResult(
                rule: rule,
                name: name,
                status: parsed,
                detail: entry["detail"] as? String ?? "",
                checkedAt: now
            )
        }
        guard !results.isEmpty else { return }
        diagnostics.record(results)
        #if DEBUG
        let url = URL.documentsDirectory.appendingPathComponent("diagnostics.txt")
        try? diagnostics.report().write(to: url, atomically: true, encoding: .utf8)
        #endif
    }
}
