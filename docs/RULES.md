# Rules

What the wrapper blocks, hides, and deliberately leaves alone. A rule is
something that **decides** what is blocked or not displayed — presentation
settings that apply to everything equally (the monochrome filter, tap-to-play,
opening to the inbox) are app behaviour, not rules, and live in
[../README.md](../README.md).

**Last updated:** 2026-10-10 · v1.7 · 6 rules

| Date | Version | Change |
| --- | --- | --- |
| 2026-10-10 | 1.7 | **R7** suggested feed cards hidden |
| 2026-10-10 | 1.4 | no rule changes — premise assertions added for R2, R3, R4 |
| 2026-10-10 | 1.3 | no rule changes |
| 2026-10-10 | 1.2 | R4 reel-queue removal |
| 2026-10-10 | 1.1 | R1, R2, R3, R5 — first blocking |

---

## Blocked — never loads

Cancelled by the navigation delegate before any request goes out.

| # | Matches | Result |
| --- | --- | --- |
| R1 | `/reels/` | redirected to `/` |
| R1 | `/reels/audio/<id>/` | redirected to `/` |
| R2 | `/reels/<shortcode>/` or `/reel/<shortcode>/` **from a DM** | **allowed** — plays |
| R2 | the same, from another reel | blocked — one hop only |
| R2 | the same, from the feed or an unknown page | blocked |
| R5 | `/reels/` or `/reels/audio/` reached by in-app routing | bounced to `/` |

Single reels use the **plural** prefix on mobile web, so `/reels/` with nothing
after it is the feed, and `/reels/<something>/` is one reel. Blocking the whole
prefix would block every reel sent to you in a DM.

## Hidden — loads, but not displayed

| # | Matches | Result |
| --- | --- | --- |
| R3 | `a[href="/reels/"]` | Reels tab never paints |
| R4 | queued reels in the reel viewer | removed, leaving only the one you opened |
| R7 | algorithmically injected feed cards | removed from the home feed |

R4 identifies a reel as a `<video>` **not** inside an `<article>`, whose nearest
ancestor contains an `a[href^="/reels/audio/"]`. With two or more present, every
sibling of the first is removed — so there is nothing to swipe to.

R7 hides an `<article>` containing a `[role="button"]` that sits **before** the
card's `[role="presentation"]` media block, contains no `<svg>`, and has text.
Every button in an organic card's header carries an icon; the Follow button on
an injected card is the only one with text and no icon. Ads are not matched —
their CTAs sit below the media and carry a chevron. If it ever matches more
than 70% of a feed of 3+ cards it hides nothing and reports instead, since
that means the discriminator broke rather than the feed being all suggestions.

This is also the home feed's only reels defence: injected cards are where reels
arrive in the feed, and a followed account's video post is technically a reel
too — so matching reel URLs here would delete real posts (architecture §4.4).

## Deliberately not blocked

| Surface | Why |
| --- | --- |
| DMs — `/direct/**` | the point of the app; no rule may hide anything here that isn't a queued reel |
| Login, 2FA, account recovery | breaking these locks you out |
| Ads | blocking them changes the terms-of-service risk profile — architecture §7.10 |
| Posts, profiles, Stories, Explore, hashtags | event discovery |
| Videos and voice notes in DMs | rules match routes and surfaces, never media |
| A followed account's video post in the feed | it is technically a reel; see "Not yet" below |

## Not yet

| Planned | Where |
| --- | --- |
| Explore-grid reels | §4.2 |
| Per-profile Reels tab (`/<user>/reels/`) | §4.2 |
| Native tab bar replacing Instagram's | §6.5 |
| Over-match self-disable | §7.6 |

No kill switch — if a rule misfires, use the real Instagram app until a fix
ships (architecture §7.6).

---

Implementation: `Plainfeed/Blocking/Rules.swift` (R1, R2) and
`BlockingScript.swift` (R3–R5). Route rules are covered by
`./scripts/test-routes.sh`. What each rule assumes, and how it fails, is in
architecture §7.6.
