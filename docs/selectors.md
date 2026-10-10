# Verified selectors

Source: live DOM dump of the logged-in **mobile-web home feed**, captured
2026-10-10 via Chrome device-mode inspect. This is the fixture behind
`Rules.swift` (§6.2).

**Caveat on provenance:** captured under a *Chrome* user agent, not mobile
Safari. Instagram serves markup by UA, so everything here is a strong hypothesis
to confirm on-device — not gospel. Re-verify before shipping each rule.

**Confirmed divergence (2026-10-10).** A second Chrome capture, of a reel opened
from a DM, came back as the **desktop post modal**: one `<video>` with 41
comment `<li>` items rendered inline, and the `aria-label="Next"` control not
even inside the dialog. A phone shows full-bleed video with comments behind a
tap. So:

| Surface | Chrome device-mode | Verdict |
| --- | --- | --- |
| Home feed, bottom bar, route shapes | matched the phone | usable — v1.1 shipped from it |
| Reel viewer | desktop modal | **not usable** |

Device-mode emulates viewport and touch but still sends a Chrome UA, and
Instagram branches on UA. Rough rule: trust it for surfaces that share a layout
across form factors, distrust it for anything with a distinct mobile-only
presentation. Overriding the UA to iOS Safari (DevTools → Network conditions)
moves it closer. **Safari Web Inspector attached to Plainfeed is authoritative**
— same engine, same UA, same session — and `isInspectable = true` shipped in
v1.0 (202610101740) to make that possible on release builds.

---

## 1. Route shapes — corrected

The dump overturned the route matrix in `architecture.md` §4.1 as originally
written. Mobile web uses the **plural** `/reels/` prefix for *both* the feed and
individual reels, and the singular `/reel/` does not appear at all:

| Observed URL | What it is | Action |
| --- | --- | --- |
| `/reels/` | the Reels feed (bottom-bar tab) | **block** |
| `/reels/audio/28720345147605790/` | audio page — a reel feed in disguise | **block** |
| `/reels/<shortcode>/` | **one reel permalink** | conditional (§2.1) |
| `/reel/<shortcode>` | not present in this capture; legacy form | treat as above |

So a rule of "block everything under `/reels/`" — which is what §4.1 said — would
have blocked individual reels too, including every reel a friend sends you in a
DM. The discriminator is **path shape, not prefix**:

```
/reels/                      → bare, no segment after      → BLOCK (the feed)
/reels/audio/<id>/           → literal "audio" segment     → BLOCK
/reels/<shortcode>/          → one opaque segment          → single reel, conditional
/reel/<shortcode>/           → legacy singular             → single reel, conditional
```

Shortcodes are `[A-Za-z0-9_-]{11}` in this sample (`<shortcode>`), so the
single-reel test is "exactly one path segment after `/reels/`, and it isn't
`audio`."

## 2. The §4.4 discriminator — confirmed, and necessary

All 8 feed cards classified:

| # | Author | `<video>` | reels href | Follow btn | "Suggested for you" | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | followed_a | — | — | no | no | organic — keep |
| 1 | advertiser_a | — | — | no | no (marked `Ad`) | ad — keep (§7.10) |
| 2 | **followed_b** | **1** | **`/reels/<shortcode>/`** | **no** | **no** | **organic video — KEEP** |
| 3 | followed_c | — | — | no | no | organic — keep |
| 4 | suggested_a | — | — | **yes** | **yes** | injected — hide |
| 5 | followed_d | 1 | — | no | no | organic video — keep |
| 6 | advertiser_b | 1 | — | no | no (marked `Ad`) | ad — keep (§7.10) |
| 7 | suggested_b | 1 | — | **yes** | **yes** | injected — hide |

Two things this settles:

**The §4.4 worry was real.** Card 2 is an account you follow, posting a video,
and its card carries `/reels/<shortcode>/`. A blanket `a[href*="/reels/"]` hide
in the feed would have deleted it — exactly the "friend posts a video about a
warehouse show" case. Confirmed, with a live example.

**The label discriminator works cleanly.** Every injected card (4, 7) has *both*
`Suggested for you` and a Follow button. Every organic card (0, 2, 3, 5) has
*neither*. No false positives, no ambiguity, and the two signals agree with each
other — so either can serve as the primary with the other as a cross-check.

Therefore the home feed needs **no reel rule at all**, only the suggested-post
rule, as §4.4 concluded.

### Rule — language-invariant (required; see architecture §5.1)

Comparing an organic card's header against an injected one shows the real
difference, and it isn't the text:

```
ORGANIC (followed_c)                      INJECTED (suggested_a)
<div role=button>                    <div role=button>
  <span role=link><img>                <span role=link><img>
  <a role=link href=/followed_c/>           <a role=link href=/suggested_a/>
  <span dir=auto> "followed_c"              <span dir=auto> "suggested_a"
  <svg aria-label=Verified>            <svg aria-label=Verified>
<div role=button>                      <span> "Suggested for you"   ← extra
  <svg aria-label="More options">    <div role=button> "Follow"     ← extra
                                     <div role=button>
                                       <svg aria-label="More options">
```

Every button in an organic header **contains an `<svg>`** (More options, Like,
Comment, Share). The Follow button is the only one in the header with **text and
no icon**. That gives a rule with no strings in it at all:

> Hide an `article` when it contains an element with `role="button"` that
> (a) appears **before** the card's `role="presentation"` media block,
> (b) contains **no `<svg>`** descendant, and
> (c) has non-empty text.

Signals used: `role` attributes, document order, `<svg>` presence. Nothing
translated, so it behaves identically in English, Spanish and Mandarin.

**Verified against all 8 captured cards:**

```
#  truth     rule
0  organic   keep     4  INJECTED  HIDE  ['Follow']
1  ad        keep     5  organic   keep
2  organic   keep     6  ad        keep
3  organic   keep     7  INJECTED  HIDE  ['Follow']
                             → matches ground truth, 8/8
```

Note both ads correctly fall through to **keep** — their "Shop now" / "Book now"
CTAs sit below the media and carry a chevron `<svg>`, so they fail (a) and (b).
That is the intended outcome: we are deliberately not ad-blocking (§7.10).

## 3. Bottom tab bar

Instagram's mobile-web bottom bar, in order, by `svg[aria-label]`:

```
Home · Search · New post · Reels · Messages · (profile avatar, no aria-label)
```

Notes that affect §6.5's native bar:

- There is **no `aria-label="Explore"`** — Search *is* the Explore entry on
  mobile web. Our native bar should collapse Explore and Search into one tab.
- There is **no `aria-label="Profile"`** — it's an avatar `<img>`.
- `aria-label="Messages"` is the DM entry, and it lives in this bar.

### The container problem

The bar has **no stable attribute anywhere in its ancestor chain** — 14 levels of
obfuscated `x1i10hfl`-style classes. The nearest thing to a hook is
`div[data-visualcompletion="ignore-dynamic"]`, which occurs 57 times across the
page and so is not selective on its own.

**Solution: `:has()`.** Define the container by what it contains, which is
durable in a way classes are not:

```css
/* hide the whole bottom bar: the element that holds both the Home and
   Reels tab links */
div:has(> div > span > div > a[href="/reels/"]):has(a[href="/"]) {
  display: none !important;
}
```

Two reasons this is better than it first looks:

1. **It works at documentStart.** Injected as a `<style>` in the L2 user script,
   `:has()` is evaluated by the page's own CSS engine before first paint — so no
   flash of the bar, which is the main thing the L1 content rule list was buying
   us. WebKit has shipped `:has()` since Safari 15.4, comfortably below our
   iOS 17 floor.
2. **Defence in depth.** Keep the L1 content-rule `css-display-none` on
   `a[href="/reels/"]` as well. If the structural walk ever fails, the Reels link
   itself is still gone and you get a bar with a hole in it rather than a Reels
   tab.

This also means §5's selector tiers gain a tier: **structural CSS via `:has()`**
sits above "generated class names" and below href matching, and is usable at
documentStart in a way JS DOM-walking is not.

## 4. Incidental findings

- `Audio is muted` appears 8 times — Instagram autoplays feed video muted. Our
  `mediaTypesRequiringUserActionForPlayback = .all` (decision #10) suppresses
  that, which is the intent.
- Ads are labelled `Ad` in the card header and are trivially selectable. We are
  **deliberately not blocking them** (§7.10) — that's the line that changes the
  ToS risk profile.
- The feed uses `<article>` as the card element. Durable and semantic; the
  upward-walk rules in §4.2 can anchor on it.
- `/p/<shortcode>/liked_by/` hrefs appear in most cards — a reliable way to
  recover a card's shortcode without depending on the media link.


---

## 4. Reel viewer (mobile UA capture, 2026-10-10)

Captured from Chrome with the UA overridden to iOS Safari, which flips
Instagram onto the mobile code path — `<html class="... touch ...">` appears,
and the layout stops being the desktop modal.

**Structure when a reel is opened from a DM:**

```
<div>            viewer root
  ├─ <div>   1 video    <- the reel you opened
  └─ <div>  14 videos   <- the "up next" queue (what you swipe into)
```

15 `<video>` elements, 15 `/reels/audio/<id>/` links, **no scroll-snap, no
pager control, no `role="dialog"`**. The queue is plain DOM, so it can simply
be removed — no gesture interception needed.

### Scoping: `<article>` separates the viewer from the feed

| Capture | `<video>` elements | inside `<article>` |
| --- | --- | --- |
| Reel viewer | 15 | **0** |
| Home feed | 4 | **4** |

Feed cards also carry `/reels/audio/` links, so without this scope the rule
would hide all but the first video-bearing feed card — deleting real posts.
`video:not(article video)` is the whole guard, and it is structural, so it
holds in any language.

### Rule

> Collect `<video>` elements not inside an `<article>`; climb each to the
> smallest ancestor containing an `a[href^="/reels/audio/"]` — that is a reel
> item. With two or more, take their common ancestor and hide every child that
> holds a reel item but not the **first** item in document order.

Simulated against both captures: viewer keeps 1 reel and drops 14; feed detects
0 items and the rule no-ops. Guards: does nothing with fewer than 2 items,
never hides a child that holds no reel, never acts when the common ancestor is
`<body>` or `<html>`.

**Assumption to confirm on device:** the opened reel is first in document
order. True in this capture. If Instagram ever reorders, containment would keep
the wrong reel — visible immediately, and the fix is one comparison.
