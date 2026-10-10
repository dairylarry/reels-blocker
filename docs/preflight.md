# Pre-flight

## Verdict: GO

Verified on the phone (2026-10-10, Safari, real account):

- **DMs can be read and sent on instagram.com mobile web.**

That was the go/no-go. It was the only question that could have killed the
project, because every other unknown is a detail of a design that's already
sound.

## Everything else was deferred to M2, on purpose

The rest of the original checklist was selector and markup questions — does an
injected feed reel carry a "Suggested for you" label, what does the single-reel
page do when it ends, how much of Explore is reels. Running those as a separate
manual exercise was wasted motion: **M2 is selector work with Safari Web
Inspector attached to the phone anyway**, so those answers arrive for free while
building the rules they inform.

What makes that safe to defer is that the two rules depending on them already
fail in the harmless direction:

| Unknown | If the assumption is wrong | Why it's survivable |
| --- | --- | --- |
| Do injected feed reels carry a suggestion label / Follow button? (§4.4) | Home-feed rule matches nothing | Degrades to "keep all feed videos" — you see some reels in the feed. The Reels tab and `/reels/` pager stay blocked at the route level regardless. |
| Does the single-reel page let you swipe onward? (§2.1) | Containment script is unnecessary | It's inert rather than wrong. Cheap insurance either way. |
| How much of Explore is reels after stripping? (§7.1) | Explore is thin | That's what the `Hide Explore` toggle is for. |

Neither can produce a broken app, only a slightly leaky one, and the §7.6
checker is built to notice exactly that.

## Resolved by the DOM capture (2026-10-10)

A logged-in mobile-web DOM dump answered most of this in one pass — see
`selectors.md`. It also **corrected a route rule that would have shipped broken**
(single reels use the plural `/reels/` prefix, so the original "block all
`/reels/*`" would have blocked every reel sent in a DM).

- [x] Home-feed card classification — discriminator confirmed on all 8 cards,
      and confirmed *necessary*: a followed account's video post does carry a
      reels URL.
- [x] Bottom-bar structure — no stable container attribute; `:has()` is the
      answer, and it works pre-paint.
- [x] Route shapes — `/reels/<shortcode>/` vs `/reels/` vs `/reels/audio/<id>/`.

## Still carried into M2

- [ ] Open a `/reels/<shortcode>/` permalink directly; observe whether it pages
      onward to a second reel (decides whether §2.1's containment script is
      load-bearing or just insurance).
- [ ] Re-verify every selector under **mobile Safari**, not Chrome device-mode —
      Instagram serves markup by UA.
- [ ] Walk every surface in §4.2 and record a verified-on date per rule (§5).
- [ ] Confirm `<input type="file">` offers a camera option — decides whether
      `NSCameraUsageDescription` is load-bearing or merely defensive (§6.4).
