import SwiftUI
import WebKit

/// Thin bridge. All behaviour lives in WebViewStore so that SwiftUI redraws
/// cannot tear down or reconfigure the web view.
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
