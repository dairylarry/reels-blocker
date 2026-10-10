# Changelog

Build number is shown in the launch banner, so a build on the phone can be
identified without plugging it into Xcode.

## v1.5 — 2026-10-10 — persistent banner

**Changed**
- The top banner is now **always visible** and carries a button into
  Diagnostics, replacing the two-finger long press. A hidden gesture is
  something you have to remember; the bar earns its few points by showing the
  running build and turning amber when an assertion fails.
- It sits in a `safeAreaInset` rather than an overlay, so it takes its own space
  instead of covering Instagram's header.

## v1.4 — 2026-10-10 — diagnostics page, premise assertions

**Added**
- **Diagnostics page.** Two-finger long press anywhere opens it. Read-only by
  design — not called Settings, because a page called Settings accretes toggles
  and we decided against those. Shows version and build permanently (previously
  only in a banner that faded after 4s), the current URL with its route
  classification *and the decision the rules made*, live assertion results, a
  persisted event log, and **Copy diagnostics** to the clipboard.
- **Premise assertions** (architecture §7.6.1). Each checks a conditional — an
  anchor that must be present plus a claim the rule depends on — so a quiet
  feed can never be mistaken for a dead selector:
  - `R3` nav bar present but holding no `/reels/` link → tab href changed
  - `R4` videos outside `<article>` that aren't reel items → detection confused
  - `R4` more than one reel surviving containment → swiping may work again
  - `R2` an unrecognised `/reels/` shape was allowed → Instagram added a reel
    surface we let through
  - `leak` anything linking to `/reels/` visible on screen — rule-independent,
    catches leaks from rules nobody thought to assert
- **Banner turns amber and stays** when an assertion fails, naming the rule,
  instead of fading after 4 seconds.
- **Event log**, 50 entries, persisted — a problem this morning is still there
  tonight. Only status *transitions* are logged, so it doesn't fill with every
  page load.

**Changed**
- Monochrome filter raised from 40% to **80%**.
- Each dynamic rule now runs in its own try/catch. Previously one exception
  killed every dynamic rule for the page's lifetime.

**Fixed**
- Registered the script message handler on `webView.configuration` rather than
  the original config object. `WKWebView` **copies** its configuration on init,
  so the original registration would never have fired and assertions would have
  silently never arrived.

## v1.3 — 2026-10-10 — monochrome filter, rules registry

**Added**
- **40% monochrome filter.** Implemented as a fixed, `pointer-events:none`
  overlay using `backdrop-filter: grayscale(.4)` rather than `filter` on
  `<html>` — a filter on an ancestor creates a containing block for
  `position:fixed` descendants, which would detach Instagram's sticky header
  and bottom bar. This desaturates what's painted behind it and touches no
  layout. Re-added on mutation in case Instagram replaces `<body>`.
- **[docs/RULES.md](RULES.md)** — registry of every rule in force: mechanism,
  what it matches, its premise, and which direction it fails in. To be updated
  in the same commit as any rule change.

**Changed**
- Anonymised real account handles and reel shortcodes in tracked docs. The
  selector analysis was quoting 8 accounts from the home feed, which revealed
  who the user follows; placeholders carry the same analytical value.

## v1.5 — 2026-10-10 — persistent banner

**Changed**
- The top banner is now **always visible** and carries a button into
  Diagnostics, replacing the two-finger long press. A hidden gesture is
  something you have to remember; the bar earns its few points by showing the
  running build and turning amber when an assertion fails.
- It sits in a `safeAreaInset` rather than an overlay, so it takes its own space
  instead of covering Instagram's header.

## v1.4 — 2026-10-10 — diagnostics page, premise assertions

**Added**
- **Diagnostics page.** Two-finger long press anywhere opens it. Read-only by
  design — not called Settings, because a page called Settings accretes toggles
  and we decided against those. Shows version and build permanently (previously
  only in a banner that faded after 4s), the current URL with its route
  classification *and the decision the rules made*, live assertion results, a
  persisted event log, and **Copy diagnostics** to the clipboard.
- **Premise assertions** (architecture §7.6.1). Each checks a conditional — an
  anchor that must be present plus a claim the rule depends on — so a quiet
  feed can never be mistaken for a dead selector:
  - `R3` nav bar present but holding no `/reels/` link → tab href changed
  - `R4` videos outside `<article>` that aren't reel items → detection confused
  - `R4` more than one reel surviving containment → swiping may work again
  - `R2` an unrecognised `/reels/` shape was allowed → Instagram added a reel
    surface we let through
  - `leak` anything linking to `/reels/` visible on screen — rule-independent,
    catches leaks from rules nobody thought to assert
- **Banner turns amber and stays** when an assertion fails, naming the rule,
  instead of fading after 4 seconds.
- **Event log**, 50 entries, persisted — a problem this morning is still there
  tonight. Only status *transitions* are logged, so it doesn't fill with every
  page load.

**Changed**
- Monochrome filter raised from 40% to **80%**.
- Each dynamic rule now runs in its own try/catch. Previously one exception
  killed every dynamic rule for the page's lifetime.

**Fixed**
- Registered the script message handler on `webView.configuration` rather than
  the original config object. `WKWebView` **copies** its configuration on init,
  so the original registration would never have fired and assertions would have
  silently never arrived.

## v1.3 — 2026-10-10 — monochrome filter, rules registry

**Added**
- **40% monochrome filter.** A fixed, `pointer-events:none` overlay using
  `backdrop-filter: grayscale(.4)` rather than `filter` on `<html>` — a filter
  on an ancestor creates a containing block for `position:fixed` descendants,
  which would detach Instagram's sticky header and bottom bar. This desaturates
  what is painted behind it and touches no layout. Re-applied on mutation in
  case Instagram replaces `<body>`.
- **[docs/RULES.md](RULES.md)** — registry of every rule in force: mechanism,
  what it matches, its premise, and which direction it fails in. Carries a
  last-updated log, and CLAUDE.md now requires it to change in the same commit
  as any rule change.

**Changed**
- Anonymised real account handles and reel shortcodes in tracked docs. The
  selector analysis quoted 8 accounts from the home feed, which revealed who
  the user follows; placeholders carry the same analytical value.

## v1.2 — 2026-10-10 — reel swipe containment

**Added**
- **Swiping between reels is dead.** Opening a reel from a DM renders the
  opened reel *plus* a queue of ~14 recommended ones already in the DOM — that
  queue is what you were swiping into. It is now removed, leaving one reel and
  nothing to swipe to. No gesture interception needed; there was no scroll-snap
  or pager to fight, just a list to truncate.
- Scoped by `<article>`: reel-viewer videos are never inside one, feed videos
  always are. Without that guard the rule would hide all but the first
  video-bearing card in the feed, deleting real posts. Verified on both
  captures — viewer keeps 1 and drops 14, feed no-ops entirely.
- MutationObserver re-applies it as Instagram appends more to the queue.

**Notes**
- Found via a capture taken with Chrome's UA overridden to iOS Safari. The
  earlier default-Chrome capture showed a desktop modal that does not exist on
  the phone, and was unusable. See selectors.md §4.
- Assumes the opened reel is first in document order — true in the capture, and
  worth watching for.

## v1.1 — 2026-10-10 — first Reels blocking

**Added**
- **Route blocking.** `/reels/` (the vertical pager) and `/reels/audio/<id>/`
  are cancelled and redirected home.
- **One-hop reel containment at the route level.** A reel opened *from a DM*
  plays; a reel opened from another reel, or from the feed, is blocked. This is
  what stops a single shared reel becoming an entry point to the endless feed.
- **Reels tab hidden** via `a[href="/reels/"]`, injected at documentStart so it
  never paints.
- **SPA route guard.** Instagram is client-routed, so tapping a reel often
  pushes history rather than producing a navigation the native delegate can
  see. `pushState`/`replaceState`/`popstate` are hooked and blocked paths
  bounce home.
- Regression test for the route rules: `./scripts/test-routes.sh`, 17 cases
  covering the plural-prefix trap, the one-hop rule, and the auth paths that
  must never be touched.

**Not yet**
- Swiping between reels *inside* the reel viewer is not blocked — that happens
  without a URL change, so it needs the page DOM to fix. Next up.
- Suggested posts, the native tab bar, settings and the kill switch.

**Safety**
- No rule touches `/direct/**`, `/accounts/**`, `/challenge/**`, `/two_factor/**`
  or `/oauth/**`. DMs and account recovery cannot break from these rules.

## v1.0 (202610101740) — 2026-10-10

**Fixed**
- **Sending a voice note crashed the app.** Recording audio needs
  `NSMicrophoneUsageDescription`; without it iOS terminates the process the
  moment the page calls `getUserMedia`. Same class of bug the camera string was
  added defensively to prevent — the microphone was simply missed. Also added
  the `requestMediaCapturePermissionFor` delegate, without which the web view
  denies capture by default and recording fails silently even with the key.

**Added**
- `webView.isInspectable = true`. Since iOS 16.4 a WKWebView is invisible to
  Safari Web Inspector unless this is set, and it's left on in release builds
  because the maintenance story for this app is "attach the inspector and fix
  the selector".

## M1 results — verified on device 2026-10-10

Passed: login survives force-quit **and** a phone reboot; DM inbox, reading and
sending; group threads; playing videos and voice notes; sending photos. The
wrapper itself is comfortable to use, which was M1's actual question.

Found:
- Sending a voice note crashed — fixed above.
- **A single reel permalink does let you swipe to other reels.** §2.1's
  containment is therefore load-bearing, not insurance, and is the first thing
  M2 builds.
- Reel video loops at the end rather than advancing on its own — only the
  deliberate swipe escapes.

## v1.0 (202610101707) — 2026-10-10 — first TestFlight build

First working shell. **No Reels blocking yet** — that's M2. This build exists to
prove the baseline is pleasant on its own before any rules are layered on.

**Added**
- SwiftUI app hosting a single `WKWebView` over instagram.com.
- Persistent `WKWebsiteDataStore`, so login survives relaunch and reboot.
- Opens to the DM inbox when signed in; to the site root when signed out.
- Inline media playback — without it every DM video hijacks the screen into
  the fullscreen player.
- Tap to play. Nothing autoplays, including feed video.
- Pull-to-refresh and edge-swipe back/forward.
- `target="_blank"` links load in place; without this most outbound links in
  bios and DMs are silently dead.
- Custom URL schemes (`instagram://`, `fb://`) are swallowed rather than
  failing visibly — these come from "open in app" banners.
- App icon, and a launch banner showing version and build.

**Known gaps**
- No blocking of any kind, so Reels are everywhere. Expected at this stage.
- Instagram's own bottom bar is still in use; the native tab bar is M3.
- No settings, no kill switch, no markup checker — M4.

**Distribution**
- First build uploaded to TestFlight (internal only). Build numbers are
  timestamps (`YYYYMMDDHHMM`) so they always increase.
- TestFlight builds expire after 90 days.

**Notes**
- Build output is pinned to `./build` via `SYMROOT` in `scripts/run-sim.sh`.
  Without the pin, `xcodebuild -scheme` writes to DerivedData while `-target`
  writes to `./build`, which makes it easy to install a stale binary and
  "verify" a change that was never installed. This happened once already.
