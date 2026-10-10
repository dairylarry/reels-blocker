import Foundation

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Shown in the launch banner so a build on the phone is identifiable
    /// without plugging it into Xcode.
    static var display: String { "Plainfeed v\(marketing) (\(build))" }
}
