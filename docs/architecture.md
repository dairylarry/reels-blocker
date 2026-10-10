# Architecture — Reels-free Instagram wrapper (iOS)

Status: **pre-implementation.** This doc answers the open design questions so the
build is mechanical. Nothing here is code yet.

Companion doc: [goal.md](goal.md).

---

## 1. What this app is actually for

Stated purpose, in priority order:

1. **DMs with people** — must work well. This is the daily driver.
2. **Finding out about cool events** — profiles, hashtag/location pages, Explore,
   Stories from accounts that post events.
3. **Not Reels.** No infinite vertical video feed, no Reels tab, no reel cards
   seeded into other surfaces.

That ordering drives several decisions below, most importantly: **Explore stays**
(goal.md says hide it; see §7.1 — that is a conflict with priority 2), and
**the DM inbox is the app's home surface**, not the feed (§7.4). The feed is a
place you navigate to deliberately.

Non-goals: posting Stories, video/voice calls, Live, Shopping, being a general
Instagram replacement for other people.

---

## 2. Your question: videos and Reels inside DMs

**Yes — and the distinction that makes it easy is route vs. media type.**

The rule for the whole app:

> **Block surfaces and routes, never media elements.**
> No rule in this app may ever target `<video>`, `<audio>`, or a media container.

Three different things arrive in a DM thread, and they are not the same thing:

| What lands in the DM | How it renders on instagram.com | Decision |
| --- | --- | --- |
| A video a friend recorded/uploaded directly | `<video>` inline in the thread, no reel URL at all | **Always allowed.** Untouched by any rule. |
| A voice note | `<audio>` / custom player in the thread | **Always allowed.** |
| A shared reel | A preview card in the thread that navigates to `/reel/<shortcode>` | **Allowed, once, contained** (see below) |
| A shared post | Preview card → `/p/<shortcode>` | **Always allowed.** |

Because the first two never touch a `/reel*` URL and never live on a Reels
surface, they are unaffected by design — not by a special case. That is the whole
reason the blocking layer is route- and surface-based.

### 2.1 Should shared reels open? Yes, with a one-hop containment rule

If a friend sends you a reel, the social cost of not being able to watch it is
real and the app looks broken. But a single reel permalink is the front door to
the infinite feed: on web, the single-reel viewer can let you keep going to the
next reel, and then you are in the exact hole you built this app to avoid.

So: **allow the reel, kill the escape hatch.**

```
/reels/                      bare — the feed        → always blocked
/reels/audio/<id>/           audio page             → always blocked
/reels/<shortcode>/          one reel               → allowed if the referring
/reel/<shortcode>/           one reel (legacy)        page is a DM thread
   …from a page that is itself a reel                → blocked ("one hop only")
```

### 2.2 ⚠️ Single reels use the *plural* prefix

This section originally said single reels live at `/reel/<id>` and the feed at
`/reels/`, so "block everything under `/reels/`" was safe. **That was wrong.**
The captured DOM (`selectors.md`) shows mobile web serving
`/reels/<shortcode>/` for an individual reel, and the singular `/reel/` form
appears nowhere.

So the prefix carries no information and the rule has to read **path shape**:

```
one segment after /reels/, and it isn't "audio"  → a single reel
nothing after /reels/                            → the feed
```

Had we shipped the prefix rule, every reel a friend sent you in a DM would have
been blocked — the exact failure this section exists to prevent.

Implementation sketch (decided, not yet written):

- In `decidePolicyFor navigationAction`, inspect the **source** URL
  (`navigationAction.sourceFrame.request.url`, falling back to `webView.url`).
  - Source under `/direct/` → `.allow`.
  - Source under `/reel/` → `.cancel`. You watched one; you are done.
  - Anything else (feed, profile, Explore) → `.cancel`, since the reel card that
    produced it should have been hidden anyway; this is a backstop.
- On `/reel/` pages only, inject a small script that removes next/previous
  affordances and prevents the viewer's scroll container from paging to a second
  item, so the containment holds even when navigation happens without a URL
  change (SPA routing — see §4.3).

Net effect: a reel from a DM plays, and when it ends you are looking at one
video with nowhere to swipe, and back returns you to the thread.

**Toggle:** `Allow reels shared in DMs` — default **on**. Turning it off makes
reel cards in threads inert and shows "blocked by <app>" in place of the preview,
rather than silently doing nothing on tap.

---

## 3. Platform decision (confirming goal.md)

SwiftUI + `WKWebView` host app, iOS 17+. Already settled in goal.md; recorded
here with the reasons that actually matter for the blocking layer:

- A PWA cannot inject script into a third-party origin. Dead end.
- A Safari Web Extension only works inside Safari, needs a container app anyway,
  and cannot open to the DM inbox or ship an app icon on the home screen.
- `WKWebView` gives: `WKContentRuleList` (native, pre-paint blocking),
  `WKUserScript` injection, a navigation delegate, and a persistent cookie store.

### 3.1 Two blocking layers, deliberately

| Layer | Mechanism | Handles | Why |
| --- | --- | --- | --- |
| **L1 — native rules** | `WKContentRuleList` compiled JSON: `css-display-none` + `block` | Static, attribute-matchable things: the Reels tab link, profile Reels tab, `/reels/` requests | Applied by WebKit **before layout**, so no flash of visible Reels. No JS cost. |
| **L2 — injected JS** | `WKUserScript` at `.atDocumentStart`, main frame, + `MutationObserver` | Anything needing structure: "hide the feed card that *contains* a link to `/reel/`" | Content rules can't walk up the DOM. React re-renders constantly, so the observer re-applies. |

L1 does as much as possible; L2 covers what L1 structurally cannot. Both read the
same rule set so there is one source of truth (§6.2).

**Ordering constraint:** rule-list compilation is async. The web view must not
load the start URL until `compileContentRuleList` has returned and the list is
added to the configuration's user content controller — otherwise the first paint
is unblocked. The launch sequence is: compile → attach → load. A visible splash
covers the compile (tens of ms, cached by WebKit after first run).

---

## 4. Blocking matrix

### 4.1 Routes

Never inject into, never block, never touch — auth and recovery must work or you
are locked out of your own account:

```
/accounts/*        /challenge/*       /two_factor/*
/oauth/*           /api/*             /graphql/*        /ajax/*
```

| Path | Action | Note |
| --- | --- | --- |
| `/` | allow | the Feed tab's destination. Not where the app opens (§7.4). |
| `/direct/inbox/`, `/direct/t/*` | **allow, never modified** | the point of the app |
| `/reels/` (bare) | **cancel → redirect `/`** | the Reels feed |
| `/reels/audio/<id>/` | cancel | audio page is a reel feed |
| `/reels/<shortcode>/` | conditional | **one reel.** Mobile web uses the *plural* prefix for single reels — see §2.2 |
| `/reel/<shortcode>` | conditional | legacy singular form, same treatment |
| `/<username>/reels/` | cancel + hide tab | profile Reels tab |
| `/explore/` | allow, reels stripped | toggle, default **on** (§7.1) |
| `/explore/tags/*`, `/explore/locations/*` | allow | primary events surface — keep |
| `/p/<shortcode>` | allow | normal posts |
| `/stories/*` | **allow, never modified** | event channel — no rule touches Stories |
| `/<username>/` | allow | profiles |

### 4.2 Surfaces where reel cards leak in

Each needs its own verified rule; they do not share markup:

1. **Home feed** — see §4.4. This is the one surface where "hide everything
   with a `/reel/` href" is the wrong rule.
2. **Explore grid** — mixed grid, reel tiles carry a video/reel indicator and a
   `/reel/` href. Hide the tile (L2).
3. **Profile grid + Reels tab** — the *profile's* own Reels tab still needs a
   rule (L1); the app-level Reels tab is gone with Instagram's bottom bar (§6.5).
4. **Search results** — reel results appear in the tabbed results.
5. **Hashtag / location pages** — same mixed grid as Explore.
6. **Suggested posts** ("Suggested for you" after the feed ends) — not Reels, but
   the same infinite-scroll hole. Hidden, no toggle (§7.3).

### 4.3 The SPA problem

Instagram is a client-routed React app. Tapping a reel card often does **not**
produce a `WKNavigationAction`; it pushes history and re-renders. So the
navigation delegate alone is not sufficient containment.

Mitigations, all three:

- `MutationObserver` re-applies hiding on every render, so the card is gone
  before it can be tapped.
- A `history.pushState` / `replaceState` / `popstate` hook in L2 checks the new
  path against the same route matrix and, on a blocked path, calls
  `history.back()` or navigates to `/`.
- The delegate stays as the backstop for real page loads and external links.

### 4.4 ⚠️ A friend's video post *is* a reel, URL and all

Since 2022 Instagram converts any video posted to feed into a Reel. So when an
account you follow posts a 30-second video about a warehouse show on Saturday,
that post lives at `/reel/<shortcode>` and renders in your feed as a reel card.

A naive "hide anything linking to `/reel/`" rule in the home feed therefore
deletes exactly the event announcements this app exists to surface. The feed rule
has to separate two things that share a URL shape:

| | What it is | Decision |
| --- | --- | --- |
| **Chronological, from an account you follow** | A friend's video post. Reels only in the technical sense. | **Keep.** Plays in place, in the feed. |
| **Algorithmically injected** — "Suggested for you", "Reels for you", from accounts you don't follow | The slot machine | **Hide** |

The discriminator is the **suggestion label**, not the URL: injected cards carry
a header label ("Suggested for you", "Reels", "Based on your activity") or a
Follow button, because Instagram has to disclose that you don't follow them.
Followed-account posts have neither. So the home-feed rule is:

> Hide a feed card when it carries a suggestion label or a Follow button —
> regardless of whether it is a reel. Otherwise keep it, reel or not.

This is the §7.3 suggested-posts rule doing double duty, and it means the home
feed needs **no reel-specific rule at all**. Nice outcome: the most
re-render-heavy, most fragile surface gets the simplest rule.

The infinite-scroll hole was never the feed anyway — it is the Reels tab and the
`/reels/` vertical pager, and both stay hard-blocked at the route level where
markup changes can't reach them.

**Verified** against a live capture — see `selectors.md` §2. All 8 feed cards
classified: both injected cards carried *both* `Suggested for you` and a Follow
button; all four organic cards carried neither. No ambiguity.

And the worry here was real, not theoretical: one organic card was an account you
follow posting a video, and it carried `/reels/<shortcode>/`. A blanket
reels-href rule in the feed would have deleted it.

Because the two signals (label, Follow button) agree with each other, the rule
requires only **one** of them — so Instagram dropping either doesn't break it. If
it ever drops both, the rule degrades to "keep all feed videos", which is the
safe direction to fail.

---

## 5. Selector strategy

Instagram ships obfuscated, rotating class names. Rules are ranked by durability
and only the top tiers are allowed:

1. **Route/href matching** — `a[href^="/reels/"]`. Durable, because the URL
   scheme is a product contract, and identical in every language.
2. **Structural ARIA** — `role="button"`, `role="presentation"`, `role="link"`.
   Durable and language-invariant. **`aria-label` values are not** — they are
   translated — so match on the *attribute's presence and role*, never its text
   (§5.1).
3. **Structural CSS via `:has()`** — "the element containing both the Home and
   Reels tab links". Defines a target by its contents rather than its classes,
   and crucially **works at documentStart**, so it hides pre-paint like an L1
   rule while matching structurally like an L2 one. WebKit has shipped `:has()`
   since Safari 15.4, well below our iOS 17 floor. This is how the bottom bar
   gets hidden (§6.5), since it has no stable attribute anywhere in 14 levels of
   ancestry.
4. **Structural walking in JS** — same idea where the match depends on *text*
   (`/suggested for you/i`), which CSS cannot express. Post-paint, hence L2.
5. **Generated class names** — **banned.** Never ship a rule keyed on `._ab1c`.

### 5.1 🔴 Hard constraint: no rule may match on text

**You switch between English, Spanish and Mandarin on your phone.** Instagram
follows the device language, so every user-visible string in the DOM is a moving
target: "Suggested for you" / "Sugerencias para ti" / "为你推荐", and
`aria-label="Home"` / `"Inicio"` / `"主页"`.

That makes text matching unusable, and it rules out the obvious workarounds:

- **Pinning `Accept-Language` to English** would work technically, but it forces
  Instagram into English permanently and fights the thing you actually do. Tried
  and reverted — see the git history for `Language.swift`.
- **A per-language label table** (en/es/zh) is maintenance debt that breaks the
  day you add a fourth language or Instagram rewords a string in one locale only.

So: **every rule is built from language-invariant signals.** In practice that is
href paths, `role` attributes, document order, element nesting, and the presence
or absence of `<svg>` — all of which Instagram ships identically in every locale.

This is a real constraint, not an aspiration: the home-feed rule was redesigned
around it and is now *stronger* than the text version it replaced
(`selectors.md` §2). Brand names that happen not to localize — "Reels" stays
"Reels" in Spanish — are **not** an exception to rely on; `a[href="/reels/"]`
costs nothing and can't drift.

The §7.6 checker may still carry a label table as a **diagnostic** — "the
structural rule stopped matching, and here's a localized label that says a
suggested post is on screen" — because a wrong diagnosis is cheap and a wrong
rule is not.

Every rule gets a comment naming the surface and the date verified, so breakage
is diagnosable a year from now.

---

## 6. Components

### 6.1 File layout (proposed)

```
Plainfeed/
  App.swift                    @main, start-URL routing, splash during compile
  ContentView.swift            web view + chrome + settings sheet
  Web/
    WebView.swift              UIViewRepresentable wrapper
    WebViewCoordinator.swift   WKNavigationDelegate, the route matrix in code
    WebViewStore.swift         owns the WKWebView instance (survives SwiftUI redraws)
    Configuration.swift        WKWebViewConfiguration, data store, UA, media flags
  Blocking/
    Rules.swift                single source of truth: routes + selectors
    ContentRuleList.swift      builds + compiles the L1 JSON
    injected.js               L2: observer, structural rules, SPA hooks
    reel-containment.js       L2, /reel/ pages only (§2.1)
  Chrome/
    TabBar.swift               native bottom bar, Inbox first (§6.5)
    TabRouter.swift            per-tab last-URL memory
  Settings/
    Prefs.swift                @AppStorage-backed toggles
    SelfTestView.swift         per-rule match table (§7.6)
    SettingsView.swift
```

### 6.2 `Rules.swift` as the single source of truth

One Swift structure describes every route decision and every selector, tagged
with which layer consumes it. `ContentRuleList.swift` renders the L1 subset to
JSON; `injected.js` receives the L2 subset as a serialized object injected ahead
of it. Nothing is written twice — a rule fix is a one-line change.

### 6.3 `WKWebViewConfiguration` — the settings that matter

| Setting | Value | Why |
| --- | --- | --- |
| `websiteDataStore` | `.default()` | persistent cookies → login survives relaunch |
| `allowsInlineMediaPlayback` | `true` | **default is false on iPhone**; without it every DM video hijacks the screen into the fullscreen player |
| `mediaTypesRequiringUserActionForPlayback` | `.all` | **tap to play.** Nothing autoplays — not feed video, not DM video. Given the whole project is about not being fed video passively, this is more on-target than matching the real site's autoplay. |
| `applicationNameForUserAgent` | mobile Safari token | WKWebView's default UA omits the `Safari` token; Instagram may serve a degraded page. Append rather than replacing the whole UA. |
| `allowsBackForwardNavigationGestures` (on the view) | `true` | edge-swipe back, required by goal.md |
| `WKAppBoundDomains` in Info.plist | **do not set** | opting in restricts `evaluateJavaScript` on non-app-bound domains and would disable the entire blocking layer |

Also needed: `UIRefreshControl` on `webView.scrollView` for pull-to-refresh, and
`contentInsetAdjustmentBehavior` tuning so the DM composer is not under the home
indicator.

### 6.4 Info.plist usage strings — ship all three even though you don't want the camera

You said no camera access needed, and you'll never use it. Ship the string
anyway, as crash defense:

| Key | Why |
| --- | --- |
| `NSPhotoLibraryUsageDescription` | sending a photo in a DM via `<input type="file">` |
| `NSPhotoLibraryAddUsageDescription` | long-press → **Save Image** on a flyer someone DMs you. Easy to forget and genuinely useful for events. |
| `NSCameraUsageDescription` | **defensive.** Instagram's own file input decides whether the picker sheet offers "Take Photo" — we don't control that. If it does and the string is missing, iOS **kills the app** on tap. |

A usage string is not a grant: iOS only prompts if something actually invokes the
camera, and you never will. The cost of including it is zero; the cost of
omitting it is a crash you'd spend an evening diagnosing.

### 6.5 Native tab bar replacing Instagram's

Instagram's bottom bar is hidden by a single CSS rule and replaced with a SwiftUI
tab bar: **Inbox · Feed · Search · Profile**, Inbox first and selected at launch.

Four tabs, not five: the capture shows mobile web has **no separate Explore
entry** — Search *is* Explore there (`selectors.md` §3) — so collapsing them is
matching the site, not cutting a corner.

The reason this is worth the work isn't aesthetics — it's that **Instagram's
bottom bar is where the Reels tab lives.** Hiding the entire bar and drawing our
own retires `a[href^="/reels/"]`, the most fragile and most important selector in
the project. One rule covering a whole container is far more durable than a rule
targeting one item inside it.

The failure mode is also the right one. If the hide-the-bar rule goes stale you
see **two tab bars** — ugly, obviously wrong, still fully usable, and the §7.6
checker flags it. Compare the alternative: a stale per-item selector silently
restores the Reels tab, which is the one outcome the app exists to prevent.

Mechanics:

- Each tab owns a URL and keeps its own last-visited path, so tab switches don't
  reload. One `WKWebView` throughout — not five — with tab switching as
  navigation plus remembered scroll offsets.
- The bar is `safeAreaInset(edge: .bottom)`, and the hide rule must also zero out
  the padding Instagram reserves for its own bar, or there's a dead gap.
- No badges. There are no notifications to badge (§7.2), and an unread count
  would require polling we decided against.
- Search doubles as Explore (above); its reel-stripped grid is reached here
  (§7.1). Profile is in the bar because its absence would be conspicuous.
- Instagram's own bar also carries **New post**. Left out of ours — posting from
  a web wrapper is a file-upload flow, not something you'd choose. One line to
  add later if you miss it.
- The hide rule itself is in `selectors.md` §3, including why it needs `:has()`
  and what the L1 fallback is when it fails.

---

## 7. Things goal.md missed or got wrong

These are the ones worth your attention before coding starts.

### 7.1 ⚠️ Hiding Explore contradicts your actual goal

goal.md requirement 3 says hide the Explore link. But Explore, hashtag pages, and
location pages are **where you find out about cool events** — priority 2 of three.

**Decided:** Explore stays in v1, reels stripped from its grid, with a
`Hide Explore` toggle (default **off**) in case it turns out to be mostly reels
once stripped. The reel-stripping itself is **not** toggleable — see §11.

### 7.2 DM push notifications are impossible in a WKWebView

Web Push on iOS works in Safari and in home-screen web apps. It **does not work
in `WKWebView`.** There is no API to get it, and no workaround that is both
reliable and within Instagram's terms.

So a DM arrives and your phone stays silent until you open the app.

**Decided: fine — no notifications wanted.** No `BGAppRefresh`, no badge count,
no polling, nothing to build. The app is silent by design and checking DMs is a
thing you do on purpose. This removes an entire subsystem from the project.

### 7.3 Suggested posts are the other infinite hole

Killing Reels but leaving "Suggested for you" past the end of the feed replaces
one endless scroll with another.

**Decided: hidden in v1, no toggle.** And per §4.4 this rule carries more weight
than it first looks — the suggestion label is also what separates an injected
reel from a friend's video post, so this single rule is the entire home-feed
strategy.

### 7.4 DMs are home — and with the native tab bar, that costs nothing

Worth being precise, since "launch at the inbox" and "make DMs the homepage"
sound like the same thing and aren't quite:

| | What it requires |
| --- | --- |
| Launch at the inbox | a start URL. One line. |
| DMs as the *root* | that, plus redirecting `/`, plus locking Instagram's home button, plus building a new door to the feed |

The second version was only ever necessary because **Instagram's own tab bar was
the default door to the feed.** The native tab bar (§6.5) replaces that bar
outright, so "home" becomes *whichever tab the app opens on* — which is the Inbox
tab, leftmost.

**So there is no `/` redirect and no bypass flag.** Both were deleted from this
design. `/` stays a perfectly legal URL; it's just the Feed tab's destination
rather than the app's root. If you tap Instagram's header logo and land on the
feed, that's a navigation you asked for.

What's actually built:

1. Start URL `/direct/inbox/`, Inbox selected in the tab bar.
2. Each tab remembers its own last URL, so switching back to Inbox returns to the
   thread list rather than reloading.
3. Back from a thread lands on the inbox — which is just the web view's own back
   stack behaving normally, given where you came from.

Total cost over "launch at the inbox": zero. The tab bar was already being built
for an unrelated reason (§6.5).

### 7.5 A "DM-only mode" (deferred to post-v1)

A mode that blocks every route except `/direct/*` and `/p/*` (so shared posts
still open). Instagram becomes a messaging app. **Deferred** — v1 ships without it. The route matrix in §4.1 is the thing that
would implement it, so the cost of adding it later is one predicate and one
toggle; nothing in v1 needs to anticipate it beyond keeping route decisions in
one place, which §6.2 already requires.

### 7.6 Staleness detection — measure the leak, assert the premise

Instagram will change its markup and some rule will stop matching. The question
is what signal tells you.

**What not to do: per-rule match counters.** The obvious design — "rule X
matched zero nodes on N visits, therefore it's stale" — is ambiguous. A dead
selector and a feed that genuinely contained no reels produce the same reading.
That means false alarms, and an alarm you learn to ignore is worse than none.

Three signals instead, in order of value.

**1. Leak detection — the primary signal.** Don't ask whether a rule fired; ask
whether the thing it exists to prevent is on screen:

> Is any element linking to `/reels/`, or any reel-viewer `<video>`, currently
> visible with a non-zero bounding box?

That is the actual user-facing failure. It's unambiguous, it needs no knowledge
of which rule was responsible, and it keeps working through any rule refactor.
One check replaces a counter per rule.

**2. Premise assertions — the diagnosis.** Every rule rests on a structural
assumption. Assert those directly, and a failure names the broken assumption
rather than merely reporting that something is wrong:

| Premise | Rule that depends on it |
| --- | --- |
| The bottom bar contains `a[href="/reels/"]` | Reels tab hiding (§6.5) |
| Feed cards are `<article>` elements | feed scoping (§4.4) |
| Reel-viewer videos are **not** inside `<article>` | containment scope (selectors.md §4) |
| A reel item contains an `a[href^="/reels/audio/"]` | containment detection |
| The opened reel is first in document order | which reel containment keeps |
| Single reels live at `/reels/<shortcode>/` | the entire route matrix (§2.2) |

This is the difference between "a rule broke" and "assumption 3 died" — minutes
instead of an evening. The **self-test screen** in Settings runs these on the
current page and shows pass/fail per premise with the date each was last
verified.

**3. Over-match guard — the one that auto-acts.** If a rule hides an
implausible share of a container, or hides anything at all inside `/direct/`,
**disable that rule automatically** and say so. Hiding too much is strictly
worse than leaking: a stray reel is a nuisance, a blank DM thread is a broken
app.

**Not doing: remote telemetry.** For a single user it detects nothing you won't
notice first, and shipping page content off-device carries real privacy and ToS
cost. See [WISHLIST.md](WISHLIST.md) for the full reasoning.

**Complementary: fixtures in the repo.** Running the rules against stored
sanitized DOM skeletons catches *our* regressions, the way
`scripts/test-routes.sh` already does for routes. It cannot catch Instagram
changing — that's what 1 and 2 are for — but it stops us breaking things
ourselves.

**No kill switch — decided 2026-10-10.** Earlier drafts called a global
"Disable all blocking" non-negotiable. It isn't, because **the real Instagram
app is already on the phone** and is a strictly better escape hatch: it covers
both "I'm stuck and need Instagram now" and "is Plainfeed the cause of this?"
A toggle would duplicate an app that's one tap away, and would need a settings
screen built to house it.

Consequences, accepted deliberately:

- If a rule misfires, the fix is a new build (~25 minutes end to end). In the
  meantime, use the real app.
- This raises the value of the **over-match guard** — a rule that hides too much
  must disable *itself*, since nothing else will.
- It also raises the value of premise assertions reporting clearly, so a broken
  build is diagnosed in one glance rather than investigated.

### 7.6.1 How an assertion is written

An assertion checks a **conditional**, never a count. A count is ambiguous —
"zero matches" could be a dead selector or a genuinely quiet feed. A conditional
is not: it pairs an **anchor** (something that must always be present) with a
**claim** (the fact the rule depends on), and only fires when the anchor is
there and the claim is false.

| Rule | Anchor | Claim | Fires when |
| --- | --- | --- | --- |
| R3 | bottom bar present (holds links to `/` and `/direct/inbox/`) | it also holds `a[href="/reels/"]` | bar exists but the Reels link doesn't — href changed, rule hides nothing |
| R2 | a navigation to a path under `/reels/` | it classified as a known shape, not `.other` | Instagram **added** a reel surface, e.g. `/reels/collection/<id>/`, which we currently allow silently |
| R4 | reel viewer open (a `<video>` outside any `<article>`) | its nearest ancestor holding `a[href^="/reels/audio/"]` exists | the audio-link anchor moved — containment inert, swiping works again |
| R4 scope | on the feed | every `<video>` is inside an `<article>` | a feed video appears outside one — R4 could start eating feed posts. Early warning for the *dangerous* direction |
| leak | any page, after rules run | nothing linking to `/reels/` is visible with a non-zero box | a leak from a rule we never thought to assert |

**What it buys.** Without assertions, a breakage goes: you notice reels, report
it, we reproduce, capture, diff, locate. With them: the banner names the dead
assumption on launch. The win is fault localisation and detection before you
notice — not magic, just knowing which premise died.

**The limit, stated plainly.** Assertions encode assumptions we thought of. A
failure mode nobody anticipated is as invisible as it is today. They are a
ratchet: each breakage teaches us one more assertion worth keeping.

### 7.6.2 Diagnostics page (planned, not built)

A **read-only** page — deliberately not called Settings, because a page called
Settings accretes toggles, and we decided against those (§7.6). Reached from a
**button in the persistent banner** at the top of the app.

An earlier draft hid it behind a two-finger long press to save screen space.
Replaced: a hidden gesture is something you have to remember, and the banner
earns its few points anyway by showing which build is running and by turning
amber when an assertion fails. The bar sits in a `safeAreaInset`, not an
overlay, so it never covers Instagram's own header.

Contents:

- Version and build, permanently visible — today that exists only in a banner
  that fades after four seconds.
- Assertion results: each premise, pass/fail, last checked.
- A bounded event log (~50 entries), persisted so a 9am problem is still there
  at 9pm: `18:04 R4 self-disabled — hid 83% of container`.
- Current URL and its route classification, which immediately separates "the
  classifier is wrong" from "something else is wrong".
- **Copy diagnostics** → clipboard. The highest-value item: it closes the loop
  from "something is wrong" to a full report, with no cable, no Web Inspector
  and no Mac.

Everything local. Nothing is sent anywhere.

**Where failures surface.** On-device, via the persistent banner — no settings
screen, nothing sent anywhere. On a premise failure the banner turns amber and
names the failed rule; its button opens the full list with pass/fail and the
time each was last checked.
The thing that reports breakage is then the same thing that reports which build
you are on, which is what you need in order to tell me about it.

### 7.7 Getting Instagram links to open in *your* app

Tap an Instagram link in Messages today and it opens Safari or the real app. You
cannot claim `instagram.com` universal links — that requires Instagram's own
`apple-app-site-association` file.

What does work:

- A **Share Extension** ("Open in <app>") so you can share any IG link into your
  wrapper from the share sheet.
- A **custom URL scheme** for your own shortcuts/automations.

Worth it in v1.1, not v1.

### 7.8 Things that simply will not work on web — accept these

- **Video and voice calls in DMs.** Web doesn't do them.
- **Posting Stories / the native camera flow.** File upload only.
- **Notes, some sticker/effect replies, a few newer DM features** — web lags.
- **Live.** Spotty.

Verify in §8 which of these you'd actually miss.

### 7.9 Remote selector updates (optional, v2)

Host the selector JSON in a gist and fetch it at launch with the baked-in copy as
fallback, so you can fix breakage from your phone without a rebuild. Adds a
network dependency and a little ToS surface area. Skip for v1 — and note it
matters *more* now there is no kill switch (§7.6), since it would cut
time-to-fix from a ~25-minute build-and-upload to about a minute.

### 7.10 Terms of service — the narrow path

Instagram's terms prohibit interfering with the service. Cosmetic client-side
hiding for personal use, with:

- no automation, no scraping, no bulk requests,
- **no ad blocking** (do not add rules targeting sponsored content — that is the
  line that changes the risk profile; note that hiding reels incidentally hides
  sponsored reels, which is fine),
- no credential handling of your own (Instagram's own login page, always),

is the low-risk corner. Personal device, personal account, no distribution. Do
not publish this to the App Store (goal.md is right that wrappers draw scrutiny,
and a public release invites a trademark complaint besides).

### 7.11 External links should leave the app

Someone DMs you a ticket link. Tapped inside the wrapper, you're now browsing
Dice or Resident Advisor inside an Instagram web view, with Instagram's back
stack, no address bar, and no way to share the page out.

**Rule:** in the navigation delegate, any navigation whose host is not
`instagram.com` (or a CDN subdomain) → `.cancel`, then present it in an
`SFSafariViewController` sheet. Swipe down and you're back in the thread exactly
where you were. This matters more for you than most people, since following
event links out of DMs is half the point of keeping the app.

Exception list: Instagram's own auth hops (Facebook login, `accountscenter`) must
stay in the web view or login breaks.

---

## 7.12 Backlog: a custom colour filter over the UI (v2)

Deferred, but recorded while the reasoning is fresh. Two ways to do it, and
they fail differently.

**A. CSS filter injected into the page.** `html { filter: grayscale(1) }` or a
hue/saturation tweak. Cheap, and it can be *selective* — desaturate the
interface while leaving photos alone, or the reverse:

```css
html   { filter: grayscale(1); }
img, video { filter: grayscale(0); }   /* keep friends' photos in colour */
```

⚠️ **The gotcha:** a `filter` on an ancestor creates a containing block for
`position: fixed` descendants, so fixed elements start positioning against the
filtered element instead of the viewport. On Instagram that means the sticky
header and bottom bar can detach and scroll with the page. Any CSS-filter
approach has to be tested against those specifically, and may need the filter
applied to a wrapper that excludes them.

**B. A native SwiftUI overlay** with a blend mode over the web view,
`.allowsHitTesting(false)` so taps pass through. Immune to the `position: fixed`
problem entirely, and it tints our own chrome (§6.5) consistently with the page
— which A cannot do. But it is uniform: no way to exclude photos and video.

**Recommendation when we get to it:** B for a tint or a wash, A for anything
selective. If the goal is the "make the phone boring" grayscale trick, A with
media excluded is the interesting version, because keeping friends' photos in
colour while draining the interface is exactly the asymmetry that makes it work.

Worth noting it composes well with the rest of the app: dark mode already
follows the device, and this would sit on top of that rather than replacing it.

---

## 8. Pre-flight: 20 minutes in mobile Safari before any code

The single biggest risk to this project is that **instagram.com mobile web is too
crippled for daily DM use**, in which case the architecture is irrelevant. Test
on your iPhone, in Safari, logged in, before opening Xcode:

- [ ] Open `/direct/inbox/`. Do threads load? Is the list usable?
- [ ] Send a text message. Send a photo from the library. Send a video.
- [ ] Receive and **play a video** a friend sent inline.
- [ ] Play a **voice note**.
- [ ] Open a **reel someone shared in a thread** — does it play? When it ends,
      can you swipe to another reel? (This calibrates §2.1's containment.)
- [ ] React to a message, reply to a specific message.
- [ ] Browse Explore and a hashtag page — how much is reels vs. posts?
- [ ] **In the home feed, do injected reels carry a "Suggested for you" label or
      a Follow button, and do followed-account video posts lack both?** This
      decides §4.4's rule.
- [ ] Is there a chronological **"Following" feed** on web (the native app has
      one)? If yes, that start URL may beat the default feed outright.
- [ ] Long-press an image in a DM — can you **Save Image**?
- [ ] View Stories. Reply to a story.
- [ ] Does Instagram gate anything behind an "open the app" interstitial?
- [ ] Note the layout: mobile web vs. desktop-UA — if mobile web is degraded, a
      desktop UA with a scaled viewport is the fallback lever.

Write results into a `docs/preflight.md`. If DMs fail here, stop and reconsider.

---

## 9. Milestones

### M0 — Pre-flight (§8)
No code. Go/no-go.

### M1 — Shell
Xcode project, SwiftUI + `WKWebView`, persistent data store, login works and
survives a relaunch and a device reboot. Inline media, pull-to-refresh, back
gesture, safe areas. **No blocking yet** — confirm the baseline is pleasant.

### M2 — Blocking
`Rules.swift`, L1 rule list (compile → attach → load ordering), L2 script with
observer and SPA hooks, navigation delegate route matrix, reel containment.
Iterate selectors against Safari Web Inspector (Develop → iPhone). Walk every
surface in §4.2.

### M3 — DM-first chrome
Start URL `/direct/inbox/`; native tab bar replacing Instagram's (§6.5) with
per-tab URL memory; suggested-posts rule (§4.4), which is also the whole
home-feed strategy. DM-only mode deferred (§7.5).

### M4 — Staleness detection
Premise assertions surfaced through the version banner, leak detection, and the
over-match self-disable (§7.6). No settings screen and no kill switch — the real
Instagram app is the escape hatch.

### M5 — Polish + install
Icon, keyboard/composer behavior in threads, external-link Safari sheet (§7.11),
Share Extension if wanted. Install via
Xcode (1-year provisioning on your paid account) or TestFlight (no cable, but
builds expire every 90 days — TestFlight is more convenient, Xcode install lasts
longer).

---

## 10. Name

**Plainfeed.** The feed without the machinery.

Constraints met: no "insta", no "gram", no reference to Instagram's marks. The
icon must not use their glyph or their gradient — keep it typographic or a simple
flat mark. Xcode project name, bundle display name, and target: `Plainfeed`.
Bundle id: `com.<you>.plainfeed`.

---

## 11. Settled decisions

| # | Decision | Answer |
| --- | --- | --- |
| 1 | Reels shared in DMs | **Allow, one-hop contained** (§2.1) |
| 2 | Explore | **Keep in v1**, reels stripped, `Hide Explore` toggle (§7.1) |
| 3 | Reel-stripping itself | **No toggle, and no kill switch.** If a rule misfires, use the real Instagram app until a fix ships (§7.6) |
| 4 | Suggested posts | **Hidden, no toggle** (§7.3) — also the home-feed rule (§4.4) |
| 5 | Push notifications | **None.** Not wanted, not built (§7.2) |
| 6 | Home surface | **Inbox tab, selected at launch.** No `/` redirect — the tab bar makes it unnecessary (§7.4) |
| 16 | App chrome | **Native tab bar** replacing Instagram's — Inbox · Feed · Explore · Search · Profile. Retires the Reels-tab selector (§6.5) |
| 7 | Markup-change detection | **Build it** — counters, two alarms, self-test screen (§7.6) |
| 8 | Video/voice calls | Out of scope — web can't anyway (§7.8) |
| 9 | Camera | Not wanted. Usage string ships anyway as crash defense (§6.4) |
| 10 | Autoplay | **Tap to play**, nothing autoplays (§6.3) |
| 11 | External links | Open in an `SFSafariViewController` sheet (§7.11) |
| 12 | Share Extension | Deferred to v1.1 (§7.7) |

| 13 | App name | **Plainfeed** (§10) |
| 14 | Stories | **Keep, untouched.** No rule, no toggle — primary event channel, and the tray is finite |
| 15 | DM-only mode | **Deferred.** Route matrix will leave room for it (§7.5) |

Nothing is open. §8 pre-flight is the next action.
