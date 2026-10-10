# Wishlist (v2+)

Ideas captured but deliberately not built. Nothing here is scheduled.

---

## Remote DOM telemetry — viable, but not in the raw form

**The ask:** periodically (say once a day on open) ship DOM information to S3,
so layout changes on Instagram's side can be inspected and selectors updated.

**Technically:** straightforward. `evaluateJavaScript` to capture, a
`BGAppRefresh` task or a check on launch, a presigned PUT to a bucket. Half a
day's work.

**Three reasons not to do it with raw DOM:**

1. **It exfiltrates your session.** The capture we already took contained a live
   `csrf_token` and your `machine_id` — that's why `reference/` is gitignored.
   A capture taken on a DM screen would also carry message content and your
   friends' handles. Shipping that to a bucket daily means a bucket
   misconfiguration becomes a real breach of your account *and* other people's
   messages. The blast radius is much larger than the problem being solved.
2. **It changes the ToS risk profile.** [architecture.md](architecture.md) §7.10
   defines the low-risk corner this project lives in: cosmetic, client-side,
   personal, no automation, no collection. Automated periodic off-device
   collection of page content is the definition of what that section says to
   avoid. Hiding a tab is not scraping; uploading the page daily is closer to it.
3. **For one user, remote adds almost nothing.** The §7.6 checker already
   detects "this rule stopped matching" on-device and shows you a banner. You
   *are* the only user — the signal reaches you instantly without a round trip
   through S3. Remote telemetry earns its keep when you can't reach the device,
   which is never here.

### What to build instead

> **Superseded in part:** architecture §7.6 now specifies leak detection and
> premise assertions instead of per-rule counters, because "did my rule match"
> is ambiguous — a dead selector and a genuinely reel-free feed read the same.
> The conclusion below still holds: nothing needs to leave the device.

**Tier 1 — ship the verdict, not the evidence.** The §7.6 checker already
computes per-rule match counts. Those are a handful of integers:

```json
{"build":"202610101748","rule":"reels-tab","matched":0,"visits":5,"surface":"/"}
```

That tells you Instagram changed something *and which rule died*, with zero
personal data leaving the device. Then attach the inspector once and fix it.
This is 95% of the value at essentially no risk, and could even go somewhere
simpler than S3 — a local log you read over Web Inspector, or a notification.

**Tier 2 — if an actual DOM sample is needed, ship a skeleton.** Strip
everything identifying and keep only what selectors are written against:

```
article > div[role=button] > a[role=link] + span[dir=auto] + svg
```

Tag names, `role` attributes, nesting, href *shapes* (`/reels/<id>/`, not the
id). No text, no attribute values, no URLs with tokens, no images. This is
exactly what §5.1's language-invariant rules match on, so a skeleton is
sufficient to diagnose and repair them — and it carries no session data, no
message content, and nothing about anyone else.

**Tier 3 — manual export, on demand.** A "copy diagnostic" button in settings
that puts a sanitized skeleton on the clipboard when something looks broken.
No background network at all, nothing periodic, and you choose each time.

**Recommendation:** Tier 1 as part of §7.6, Tier 3 as a small addition. Tier 2
only if 1 and 3 prove insufficient in practice. Raw DOM to S3: no.

---

## Custom colour filter over the UI

See [architecture.md](architecture.md) §7.12 — written up with the
`position: fixed` containing-block gotcha that constrains the approach.

---

## Smaller ideas

- **Share Extension** — "Open in Plainfeed" from the share sheet, so Instagram
  links from Messages don't open Safari or the real app (architecture §7.7).
- **DM-only mode** — blocks everything except `/direct/**` and `/p/**`
  (architecture §7.5). Deferred from v1; the route matrix already supports it.
- **Remote selector updates** — fetch the rule set from a gist at launch so
  breakage can be fixed without a rebuild (architecture §7.9). Note this has a
  milder version of the same ToS consideration as DOM telemetry, but it's
  pull-only and carries no user data.
