#!/usr/bin/env python3
"""Turn a captured Instagram page into a committable structural skeleton.

Keeps exactly what the rules match on — tag names, `role`, nesting, and the
*shape* of hrefs — and discards everything else: text, class names, ids, src
URLs, alt text, inline styles. The output carries no session data, no message
content, and nothing identifying about anyone.

    ./scripts/skeletonize.py reference/capture.rtf docs/samples/feed.skeleton.txt
"""
import re, sys, subprocess
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta',
        'param','source','track','wbr'}
KEEP_ATTRS = ('role', 'aria-modal', 'aria-hidden', 'dir', 'type', 'tabindex')

# Tags that carry structural meaning for the rules. A node is kept if it is one
# of these, carries one of KEEP_ATTRS, or has an href — plus every ancestor of
# a kept node. Chains of uninteresting wrapper divs collapse to one line, which
# is what keeps the output readable without hiding anything that matters.
INTERESTING_TAGS = {'video', 'audio', 'article', 'a', 'button', 'svg', 'canvas',
                    'ul', 'ol', 'li', 'form', 'input', 'textarea', 'header',
                    'nav', 'main', 'section', 'img'}

def href_shape(h):
    """Normalise a URL to its shape. No ids, no tokens, no usernames."""
    if not h.startswith('/'):
        return '<external>'
    rules = [
        (r'^/reels/audio/\d+/?$',            '/reels/audio/<id>/'),
        (r'^/reels/?$',                      '/reels/'),
        (r'^/reels/[A-Za-z0-9_-]+/?$',       '/reels/<shortcode>/'),
        (r'^/reel/[A-Za-z0-9_-]+/?$',        '/reel/<shortcode>/'),
        (r'^/p/[A-Za-z0-9_-]+/liked_by/?$',  '/p/<shortcode>/liked_by/'),
        (r'^/p/[A-Za-z0-9_-]+/?$',           '/p/<shortcode>/'),
        (r'^/stories/[^/]+/\d+/?$',          '/stories/<user>/<id>/'),
        (r'^/direct/t/\d+/?$',               '/direct/t/<id>'),
        (r'^/direct/inbox/?$',               '/direct/inbox/'),
        (r'^/explore/tags/[^/]+/?$',         '/explore/tags/<tag>/'),
        (r'^/explore/?$',                    '/explore/'),
        (r'^/$',                             '/'),
        (r'^/[A-Za-z0-9._]+/reels/?$',       '/<user>/reels/'),
        (r'^/[A-Za-z0-9._]+/?$',             '/<user>/'),
    ]
    for pat, out in rules:
        if re.match(pat, h):
            return out
    return '<other-path>'

class Node:
    __slots__ = ('tag', 'attrs', 'kids', 'parent', 'keep')
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.kids, self.parent = tag, attrs, [], parent
        self.keep = False

class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node('document', {}, None)
        self.cur = self.root
        self.count = 0
    def handle_starttag(self, tag, attrs):
        self.count += 1
        n = Node(tag, dict(attrs), self.cur)
        self.cur.kids.append(n)
        if tag not in VOID:
            self.cur = n
    def handle_endtag(self, tag):
        c = self.cur
        while c is not None and c.tag != tag:
            c = c.parent
        if c is not None and c.parent is not None:
            self.cur = c.parent

def interesting(n):
    if n.tag in INTERESTING_TAGS:
        return True
    return any(k in n.attrs for k in KEEP_ATTRS) or 'href' in n.attrs

def mark(n):
    """Keep a node if it or any descendant is interesting."""
    keep = interesting(n)
    for k in n.kids:
        if mark(k):
            keep = True
    n.keep = keep
    return keep

def sig(n):
    bits = []
    for k in KEEP_ATTRS:
        if k in n.attrs:
            bits.append(f'{k}={n.attrs[k]}')
    if 'href' in n.attrs:
        bits.append(f'href={href_shape(n.attrs["href"])}')
    if n.tag == 'svg' and 'aria-label' in n.attrs:
        bits.append('aria-label=<text>')      # presence only, never the value
    return f'<{n.tag}>' + (' ' + ' '.join(bits) if bits else '')

def render(n, depth, out):
    kept = [k for k in n.kids if k.keep]
    # collapse a chain of uninteresting single-child wrappers
    if not interesting(n) and len(kept) == 1 and n.parent is not None:
        chain = 1
        cur = kept[0]
        while (not interesting(cur) and len([k for k in cur.kids if k.keep]) == 1):
            cur = [k for k in cur.kids if k.keep][0]
            chain += 1
        out.append('  ' * depth + f'<{n.tag}> ...x{chain} wrappers')
        render(cur, depth + 1, out)
        return
    out.append('  ' * depth + sig(n))
    for k in kept:
        render(k, depth + 1, out)

def collapse(lines):
    """Fold runs of identical sibling signatures into one `x N` line."""
    out, i = [], 0
    while i < len(lines):
        j = i
        while j + 1 < len(lines) and lines[j + 1] == lines[i]:
            j += 1
        n = j - i + 1
        out.append(lines[i] + (f'   x {n}' if n > 1 else ''))
        i = j + 1
    return out

def main():
    src, dst = sys.argv[1], sys.argv[2]
    if src.endswith('.rtf'):
        html = subprocess.run(['textutil', '-convert', 'txt', '-stdout', src],
                              capture_output=True, text=True).stdout
    else:
        html = open(src, encoding='utf-8', errors='replace').read()
    t = Tree(); t.feed(html)
    mark(t.root)
    lines = []
    for k in [x for x in t.root.kids if x.keep]:
        render(k, 0, lines)
    body = collapse(lines)
    header = [
        f'# Structural skeleton — {dst.split("/")[-1]}',
        '#',
        '# Generated by scripts/skeletonize.py from a logged-in capture.',
        '# Contains tag names, role attributes, nesting and href SHAPES only.',
        '# No text, class names, ids, src URLs, tokens, handles or message content.',
        f'# Nodes: {t.count} parsed, {len(lines)} kept  (identical sibling runs folded as "x N")',
        '',
    ]
    open(dst, 'w').write('\n'.join(header + body) + '\n')
    print(f'{src} -> {dst}  ({len(body)} lines from {t.count} nodes)')

if __name__ == '__main__':
    main()
