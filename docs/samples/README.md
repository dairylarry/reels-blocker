# DOM skeletons

Committable structural snapshots of the surfaces the rules operate on, so
"what did this look like when the rule worked?" is answerable by diffing rather
than re-deriving.

Generated from logged-in captures with:

```sh
./scripts/skeletonize.py reference/<capture>.rtf docs/samples/<name>.skeleton.txt
```

## What they contain

Tag names, nesting, `role` / `dir` / `type` / `tabindex` / `aria-hidden`, and
href **shapes** (`/reels/audio/<id>/`, `/<user>/`, `<external>`).

## What is stripped

Text content, class names, ids, `src` URLs, `alt` text, inline styles, and every
`aria-label` **value** (presence is recorded as `aria-label=<text>`, because the
rules may depend on a label existing but never on what it says — §5.1).

Nothing identifying survives: no handles, no shortcodes, no CSRF token, no
message content. The raw captures stay in `reference/`, which is gitignored.

## Current snapshots

| File | Surface | Key facts |
| --- | --- | --- |
| `home-feed.skeleton.txt` | home feed, mobile | 8 `<article>`, 4 `<video>` (all inside articles) |
| `reel-viewer.skeleton.txt` | reel opened from a DM | 15 `<video>`, **0 `<article>`**, 28 audio links |

Those two numbers are the premise behind R4's scope: viewer videos are never
inside an `<article>`, feed videos always are. If a future capture breaks that,
R4's scoping is wrong and the feed is at risk — see [../RULES.md](../RULES.md).
