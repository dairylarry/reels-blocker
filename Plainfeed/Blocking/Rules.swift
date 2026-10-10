import Foundation

/// Single source of truth for what is blocked (architecture §6.2).
///
/// Everything here is language-invariant: paths and structure only, never
/// user-visible text (§5.1), because the device language moves between
/// English, Spanish and Mandarin.
enum Rules {

    // MARK: - Route classification

    enum Route: Equatable {
        case reelsFeed          // /reels/            — the vertical pager
        case reelsAudio         // /reels/audio/<id>/ — an audio page is a reel feed
        case singleReel         // /reels/<shortcode>/ or /reel/<shortcode>/
        case directMessages     // /direct/**
        case auth               // never touched — breaking this locks you out
        case other
    }

    /// Paths that must never be blocked or modified. Getting this wrong means
    /// being unable to log in or recover the account.
    private static let authPrefixes = [
        "/accounts/", "/challenge/", "/two_factor/", "/oauth/",
        "/api/", "/graphql/", "/ajax/",
    ]

    static func classify(_ url: URL) -> Route {
        let path = url.path.hasSuffix("/") ? url.path : url.path + "/"

        if authPrefixes.contains(where: { path.hasPrefix($0) }) { return .auth }
        if path.hasPrefix("/direct/") { return .directMessages }

        // NOTE: mobile web uses the PLURAL prefix for single reels —
        // /reels/<shortcode>/ — so the prefix carries no information and the
        // shape has to be read instead. Blocking all of /reels/* would block
        // every reel sent in a DM. See selectors.md §1.
        if path == "/reels/" { return .reelsFeed }
        if path.hasPrefix("/reels/audio/") { return .reelsAudio }

        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        if segments.count == 2, segments[0] == "reels" || segments[0] == "reel" {
            return .singleReel
        }
        return .other
    }

    // MARK: - Navigation policy

    enum Decision { case allow, blockToHome }

    /// `source` is the page the navigation came from, which is what makes the
    /// one-hop rule possible: a reel reached from a DM plays, a reel reached
    /// from another reel does not.
    static func decide(destination: URL, source: URL?) -> Decision {
        switch classify(destination) {
        case .auth, .directMessages, .other:
            return .allow

        case .reelsFeed, .reelsAudio:
            return .blockToHome

        case .singleReel:
            guard let source else { return .blockToHome }
            switch classify(source) {
            case .directMessages:
                return .allow        // a friend sent it — play it
            case .singleReel:
                return .blockToHome  // one hop only; this is the rabbit hole
            default:
                return .blockToHome  // the card should have been hidden anyway
            }
        }
    }

    /// A `/reels/`-prefixed path we do not recognise — meaning Instagram added
    /// a reel surface we currently allow through. The R2 premise (§7.6.1).
    static func isUnknownReelShape(_ url: URL) -> Bool {
        let path = url.path.hasSuffix("/") ? url.path : url.path + "/"
        guard path.hasPrefix("/reels/") || path == "/reels/" else { return false }
        return classify(url) == .other
    }

    static let home = URL(string: "https://www.instagram.com/")!
}
