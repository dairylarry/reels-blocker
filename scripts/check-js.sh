#!/bin/bash
# Syntax-check the JavaScript embedded in BlockingScript.swift.
#
# The script lives inside a Swift multiline string, so Swift only validates its
# ESCAPES, never its JavaScript. A malformed rule would compile fine and then
# silently do nothing on the device. This extracts the literal, resolves the
# interpolations, and runs it through node.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
python3 - "$OUT/blocking.js" <<'PY'
import re, sys
src = open('Plainfeed/Blocking/BlockingScript.swift').read()
m = re.search(r'private static let source = """\n(.*?)\n    """', src, re.S)
assert m, 'could not find the embedded script'
js = m.group(1)
# resolve Swift interpolations with stand-ins
js = js.replace(r'\(messageHandler)', 'plainfeed')
js = js.replace(r'\(jsString(css))', '"/* css */"')
# a Swift literal's \\ is one backslash in the real string
js = js.replace('\\\\', '\\')
assert '\\(' not in js, 'unresolved Swift interpolation: ' + js[js.index('\\('):][:40]
open(sys.argv[1], 'w').write(js)
print(f'extracted {len(js.splitlines())} lines of JavaScript')
PY

node --check "$OUT/blocking.js"
echo "JS SYNTAX OK"
