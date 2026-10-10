import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WebViewStore

    var body: some View {
        WebView(webView: store.webView)
            .ignoresSafeArea(.container, edges: .bottom)
            // safeAreaInset rather than overlay: the bar takes its own space
            // instead of covering Instagram's header.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    VersionBanner(alert: store.diagnostics.failureSummary) {
                        store.showDiagnostics = true
                    }
                    if store.isLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.secondary)
                    }
                }
            }
            .task { store.loadStart() }
            .sheet(isPresented: $store.showDiagnostics) {
                DiagnosticsView().environmentObject(store.diagnostics)
            }
    }
}
