import Foundation

/// Every URL and host decision in one place. The route matrix (§4.1) will land
/// here in M2; for M1 this is just "where do we start and what counts as home".
enum Site {
    static let host = "www.instagram.com"

    /// Hosts we keep inside the web view. Everything else goes out to Safari
    /// in M5 (§7.11) — for now non-Instagram links still load in place.
    static let ownedHostSuffixes = [
        "instagram.com",
        "cdninstagram.com",
        "fbcdn.net",
        // Auth hops. These must stay in the web view or login breaks (§7.11).
        "facebook.com",
        "accountscenter.instagram.com",
    ]

    static func isOwned(_ url: URL) -> Bool {
        guard let h = url.host?.lowercased() else { return false }
        return ownedHostSuffixes.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    enum Tab {
        case inbox, feed, explore, search, profile

        var url: URL {
            var c = URLComponents()
            c.scheme = "https"
            c.host = Site.host
            c.path = path
            return c.url!
        }

        var path: String {
            switch self {
            case .inbox:   return "/direct/inbox/"
            case .feed:    return "/"
            case .explore: return "/explore/"
            case .search:  return "/explore/search/"
            case .profile: return "/"   // resolved to the real handle in M3
            }
        }
    }

    /// DMs are home (§7.4). Not a redirect — just where the app opens.
    static let start = Tab.inbox.url

    /// Where to land when there's no session yet.
    ///
    /// Opening straight to `/direct/inbox/` while logged out bounces through a
    /// login page carrying a `next=` redirect, and that flow misbehaves —
    /// Instagram can report a valid account as nonexistent. Signed-out users
    /// get the root instead, which is the path Instagram expects.
    static let signedOutStart = Tab.feed.url

    /// Instagram's session cookie. Presence means "already logged in".
    static let sessionCookieName = "sessionid"
}
