import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore

    var body: some View {
        WebView(webView: store.webView)
            .ignoresSafeArea(.container, edges: .bottom)
            // Opt out of SwiftUI's keyboard avoidance. Without this, showing
            // the keyboard resizes the web view, and a frame change while an
            // input is focused can make WebKit resign first responder — the
            // keyboard appears and immediately drops again. WKWebView manages
            // its own keyboard insets, so SwiftUI doing it too is both
            // redundant and harmful.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // safeAreaInset rather than overlay: the bar takes its own space
            // instead of covering Instagram's header.
            .safeAreaInset(edge: .top, spacing: 0) {
                // The progress bar is an OVERLAY on the banner, not stacked
                // below it, so the inset's height never changes.
                //
                // It used to be a VStack. When a page finished loading the
                // ProgressView disappeared, the inset shrank by 34pt and the
                // web view's frame grew — and a frame change while an input is
                // focused makes WebKit resign first responder. That dropped the
                // keyboard in the DM recipient search, the one place you tap a
                // field while a page is still loading.
                VersionBanner(alert: store.diagnostics.failureSummary) {
                    store.showDiagnostics = true
                }
                .overlay(alignment: .bottom) {
                    if store.isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.8))
                            .frame(height: 2)
                    }
                }
            }
            .task { store.loadStart() }
            // Same treatment as the in-page "That's everything." overlay, so
            // the two messages read as one voice. Kept native rather than
            // injected so it still appears if the page is mid-load.
            .overlay(alignment: .center) {
                if let toast = store.toast {
                    Text(toast)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                        .padding(.horizontal, 20)
                        .background(.black.opacity(0.58))
                        .background(.ultraThinMaterial)
                        .offset(y: -60)          // ~42% of height, as in CSS
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.toast)
            .sheet(isPresented: $store.showDiagnostics) {
                DiagnosticsView().environmentObject(store.diagnostics)
            }
    }
}
