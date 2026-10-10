# Project: Reels-free Instagram wrapper (iPhone)

## Goal
Build a personal iOS app that loads Instagram and removes Reels, similar in concept to SocialLite (sociallite.app). Original name, branding, and UI. Don't copy theirs.

## How comparable apps work (inferred from their sites)
SocialLite, Dull, and No Reel for Instagram all embed instagram.com in an in-app browser and strip the Reels UI. SocialLite also ships a Chrome extension with "Block Reels" and "Block Explore" toggles. Their internals aren't documented, so this is inference.

## Decision: native iOS app with WKWebView
- A PWA can't work. It can't run scripts on a third-party origin like instagram.com.
- A Safari Web Extension is possible but only works inside Safari and still needs a container app.
- Native SwiftUI + WKWebView gives full control over script injection, navigation, and persistent login.

## Requirements
1. SwiftUI app hosting a WKWebView that loads https://www.instagram.com.
2. Use the default persistent WKWebsiteDataStore so the login persists.
3. Inject a WKUserScript (atDocumentStart, main frame) that:
   - hides the Reels tab link (a[href="/reels/"]) and the Explore link
   - hides Reels cards in the feed, on profiles, and on Explore
   - uses a MutationObserver to re-apply as Instagram's React UI re-renders
   - prefers href/attribute matching over class names, which change often
4. WKNavigationDelegate: cancel navigation to /reels/* and redirect to "/".
5. Optional: allow single-reel links (/reel/<id>) so Reels friends send in DMs still open.
6. Support the mobile viewport, safe areas, pull-to-refresh, and a back/forward gesture.

## Known limitations
- Web Instagram only: no native camera (file upload for posting), limited push notifications.
- Instagram can change its markup at any time, so selectors need occasional maintenance.
- Modifying Instagram's UI may violate its terms of service. This is a gray area, so personal use is the safest.

## Distribution
- Personal use: build in Xcode and install on my own iPhone. A free Apple ID works but the install expires every 7 days. A $99/year developer account removes that and allows TestFlight.
- App Store submission is possible, but web wrappers get extra review scrutiny.

## First steps
1. Create the Xcode project (SwiftUI, iOS 17+).
2. Get the WKWebView loading and logged in.
3. Add the injected CSS/JS and iterate on selectors using Safari's Web Inspector (Develop menu → iPhone).
4. Add navigation blocking, then polish.