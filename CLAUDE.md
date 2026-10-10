# Working in this repo

## Versioning — bump on every changelog entry

**Every time something is added to [docs/CHANGELOG.md](docs/CHANGELOG.md), bump
`MARKETING_VERSION` first.** One changelog entry = one version. Never append to
a version that has already been uploaded to TestFlight.

```sh
./scripts/bump.sh 1.1     # updates MARKETING_VERSION in both build configs
```

Then write the entry under that version heading, then upload.

- `MARKETING_VERSION` (1.0 → 1.1 → 1.2) is the human-facing version and is what
  gets bumped. Started at 1.0.
- `CURRENT_PROJECT_VERSION` is the build number and is set automatically to a
  `YYYYMMDDHHMM` timestamp by `scripts/testflight.sh`. Never set it by hand —
  App Store Connect requires it to strictly increase.
- Both appear in the launch banner as `Plainfeed v<marketing> (<build>)`, so a
  build on the phone can always be traced back to a changelog entry.

## Builds

Use the scripts, not raw `xcodebuild`:

```sh
./scripts/run-sim.sh                      # simulator
TEAM_ID=T3TPJL55B5 ./scripts/testflight.sh   # archive + upload
```

`run-sim.sh` pins `SYMROOT` to `./build`. Without the pin, `xcodebuild -scheme`
writes to DerivedData while `-target` writes to `./build`, which makes it easy
to install a stale binary and "verify" a change that was never installed.

When running `testflight.sh`, **do not pipe its output through `head`** — the
pipe closes, the script takes SIGPIPE and dies mid-upload, leaving a good
archive with no export. Filter with `grep` alone, or let it run.

## Rules for blocking rules

Any rule change updates [docs/RULES.md](docs/RULES.md) in the same commit,
including a new row in its log table at the top.

Prefer a **navigation** rule over a **DOM** rule when both could express the
same intent — navigation rules depend only on URL shapes and survive redesigns;
DOM rules are the fragile layer.


See [docs/architecture.md](docs/architecture.md) §5.1. The hard one:
**no rule may match on user-visible text.** The device language changes between
English, Spanish and Mandarin, so every rule is built from hrefs, `role`
attributes, document order, and element structure only.
