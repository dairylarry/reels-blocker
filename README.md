# Plainfeed

An iOS wrapper around instagram.com with Reels removed. Personal use.

DMs are the home surface; the Reels tab and the `/reels/` vertical feed are
blocked at the route level; a reel someone sends you in a DM still plays.

- [docs/architecture.md](docs/architecture.md) — design, decisions, and why
- [docs/RULES.md](docs/RULES.md) — what is blocked, hidden, and deliberately left alone
- [docs/selectors.md](docs/selectors.md) — verified selectors against captured DOM
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — what shipped in each build
- [docs/WISHLIST.md](docs/WISHLIST.md) — v2+ ideas, captured not scheduled

## App behaviour (not rules)

Things that apply to everything equally, rather than deciding what to block:

- Opens to the DM inbox when signed in, the site root when signed out
- **Nothing autoplays** — feed and DM video both wait for a tap
- Media plays inline instead of hijacking the screen into the fullscreen player
- Everything rendered **80% monochrome** (a `backdrop-filter` overlay, chosen so
  it cannot disturb layout — see architecture §7.12)
- Login persists across relaunch and reboot
- A persistent banner at the top shows the running version and opens
  Diagnostics; it turns amber and names the rule when an assertion fails

What decides whether something is blocked or hidden is in
[docs/RULES.md](docs/RULES.md).

## Project facts

| | |
| --- | --- |
| Bundle ID | `com.barryyang.plainfeed` |
| Apple Team ID | `T3TPJL55B5` |
| Deployment target | iOS 17, iPhone only, portrait |
| Signing | Automatic |

The Team ID is not a secret — it ships inside every build and is readable from
any IPA. Credentials that must **never** be committed: App Store Connect API
keys (`.p8`), certificate exports (`.p12`), private keys, app-specific
passwords. `.gitignore` covers `reference/` (authenticated page dumps with live
CSRF tokens) and build output.

## Shipping a change

The whole loop, in order. Each step matters; the notes under each are things
that have actually gone wrong.

```sh
# 1. make the change, then check it on the simulator
./scripts/run-sim.sh

# 2. if route rules changed
./scripts/test-routes.sh

# 3. bump the version — one changelog entry = one version
./scripts/bump.sh 1.5

# 4. write the entry in docs/CHANGELOG.md
#    and update docs/RULES.md (+ its log table) if any rule changed

# 5. archive, sign and upload
TEAM_ID=T3TPJL55B5 ./scripts/testflight.sh
```

**Do not pipe `testflight.sh` through `head`.** The pipe closes, the script
takes SIGPIPE and dies mid-upload, leaving a good archive and no export. Filter
with `grep` alone, or let it run.

**If the upload half fails or gets interrupted,** the archive is still good —
re-run only the export:

```sh
xcodebuild -exportArchive -archivePath build/Plainfeed.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```

**Build numbers** are timestamps set automatically by the script, so they always
increase. App Store Connect rejects a repeat.

**After upload:** processing takes 5–15 minutes. Then App Store Connect →
TestFlight → Pruebas internas → `internal` → Compilaciones, and add the build if
it is not there. Turning on automatic distribution for that group, and
Automatic Updates in TestFlight on the phone, removes this step for good.

## Running on your iPhone directly

Only needed for Web Inspector or to skip the TestFlight round trip.

1. Xcode → Settings → Accounts → sign in with the developer Apple ID.
2. Open `Plainfeed.xcodeproj` → select the **Plainfeed** target (under TARGETS,
   not PROJECT) → Signing & Capabilities → Team.
3. Connect the iPhone by cable, unlock, **Trust**.
4. On the phone: Settings → Privacy & Security → **Developer Mode** → on, then
   reboot. Without it the app installs and then refuses to launch.
5. Pick the phone as the run destination and ⌘R.

## When something breaks

Instagram changes its markup; rules go stale. There is **no kill switch** — if
the app misbehaves, use the real Instagram app until a fix ships.

**1. Get the diagnostics.** Tap the stethoscope button in the banner at the top
of the app. Tap **Copy diagnostics** and paste it somewhere useful. It
contains the version, the current URL and route decision, every premise
assertion with pass/fail, and a persisted event log. A failing assertion names
the dead assumption, which is usually the whole diagnosis.

**2. Re-capture the DOM.** Two ways, and they are not equivalent:

- **Safari Web Inspector against the app** — authoritative. Same engine, same
  UA, same session. Mac Safari → Develop → *your iPhone* → Plainfeed →
  Elements → right-click `<html>` → Copy → Outer HTML. Requires Developer Mode
  on and the phone reachable. `isInspectable = true` ships in release builds
  specifically so this works on TestFlight.
- **Chrome device mode** — convenient but only trustworthy if you override the
  user agent to iOS Safari (DevTools → ⋮ → More tools → Network conditions).
  With the default Chrome UA, Instagram serves desktop markup for some surfaces
  — the reel viewer especially. See docs/selectors.md.

**3. Save the capture to `reference/`** — gitignored, because these dumps carry
a live CSRF token and your `machine_id`. Never commit one.

**4. Skeletonise and diff:**

```sh
./scripts/skeletonize.py reference/new-capture.rtf /tmp/new.skeleton.txt
diff docs/samples/home-feed.skeleton.txt /tmp/new.skeleton.txt
```

The committed skeletons in `docs/samples/` are what the rules were written
against. The diff usually shows the change directly. Skeletons carry no text,
class names, handles or tokens — safe to commit, so update them when a surface
changes for real.

**5. Crash reports**, for native crashes only (not stale rules — those never
crash): Xcode → Window → Organizer → Crashes, symbolicated automatically since
`ExportOptions.plist` sets `uploadSymbols`. Requires Settings → Privacy &
Security → Analytics & Improvements → **Share With App Developers** on the
phone.

## Coming back to this after a long break

- **The Apple Developer membership is $99/year.** If it lapses, TestFlight
  builds stop working and you cannot upload. Renew before expiry.
- **Signing certificates last about a year.** If archiving fails with a signing
  error, Xcode → Settings → Accounts → Manage Certificates usually fixes it, and
  `-allowProvisioningUpdates` (already in the script) lets it regenerate.
- **TestFlight builds expire after 90 days.** An expired build just needs a new
  upload — no other work.
- **The device must stay registered** on the developer portal for archiving to
  work, because the archive is signed with a development identity before export
  re-signs it for the App Store. A new phone means registering its UDID at
  developer.apple.com → Devices.
- **Rules will have rotted.** Open the app, tap the stethoscope, read the
  assertions. That tells you what still holds before you change anything.
- **Read [docs/RULES.md](docs/RULES.md) first** — it is the short version.
  [docs/architecture.md](docs/architecture.md) has the reasoning behind every
  decision, including ones deliberately *not* taken.

## Repo layout

```
Plainfeed/
  Blocking/      Rules.swift (routes) + BlockingScript.swift (injected CSS/JS)
  Diagnostics/   DiagnosticsStore.swift, DiagnosticsView.swift
  Web/           WKWebView setup, navigation delegate, message handler
  Config/        Site.swift (URLs), AppVersion.swift
docs/            architecture, RULES, selectors, CHANGELOG, WISHLIST
docs/samples/    committed DOM skeletons (sanitised, safe)
reference/       raw captures — GITIGNORED, contains live tokens
scripts/         run-sim, testflight, bump, test-routes, skeletonize
```
