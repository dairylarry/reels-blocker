import SwiftUI

@main
struct PlainfeedApp: App {
    @StateObject private var store = WebViewStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
