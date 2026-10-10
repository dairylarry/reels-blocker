import WebKit

enum BlockingScript {

    /// Name the injected script posts assertion results to.
    static let messageHandler = "plainfeed"


    /// Injected at documentStart so the CSS applies before first paint and the
    /// history hooks are installed before Instagram's router runs.
    static func userScript() -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Href-based only — identical in every language (§5.1).
    private static let css = """
    a[href="/reels/"], a[href="/reels"] { display: none !important; }
    [data-plainfeed-hidden] { display: none !important; }

    /* 40% monochrome. A display setting, not a blocking rule — it decides
       nothing, it tints everything equally.
       backdrop-filter on a fixed overlay, NOT filter on <html>: a filter on an
       ancestor creates a containing block for position:fixed descendants, which
       detaches Instagram's sticky header and bottom bar from the viewport.
       This desaturates everything painted behind it and touches no layout. */
    #plainfeed-mono {
      position: fixed;
      inset: 0;
      z-index: 2147483647;
      pointer-events: none;
      -webkit-backdrop-filter: grayscale(0.8);
      backdrop-filter: grayscale(0.8);
    }
    """

    private static let source = """
    (function () {
      'use strict';

      // --- CSS, before first paint -------------------------------------
      var style = document.createElement('style');
      style.setAttribute('data-plainfeed', '1');
      style.textContent = \(jsString(css));
      (document.head || document.documentElement).appendChild(style);

      // --- monochrome overlay (display setting, not a rule) ------------
      // Appended to <body>, so it waits for one to exist.
      function mono() {
        if (document.getElementById('plainfeed-mono')) return;
        if (!document.body) return;
        var layer = document.createElement('div');
        layer.id = 'plainfeed-mono';
        layer.setAttribute('aria-hidden', 'true');
        document.body.appendChild(layer);
      }

      // --- SPA route guard ---------------------------------------------
      // Instagram is client-routed, so tapping a reel often pushes history
      // instead of producing a navigation the native delegate can see. These
      // paths are the vertical pager itself and are never legitimate.
      var BLOCKED = /^\\/reels\\/?$|^\\/reels\\/audio\\//;

      function guard() {
        try {
          if (BLOCKED.test(location.pathname)) { location.replace('/'); }
        } catch (e) {}
      }

      ['pushState', 'replaceState'].forEach(function (name) {
        var original = history[name];
        history[name] = function () {
          var result = original.apply(this, arguments);
          guard();
          return result;
        };
      });

      window.addEventListener('popstate', guard);
      guard();

      // --- Reel containment --------------------------------------------
      // Opening a reel from a DM renders the opened reel PLUS a queue of
      // recommended ones, all in the DOM — that queue is what you swipe into.
      // Measured structure (selectors.md §4):
      //
      //   <div>            viewer root
      //     <div>  1 video     <- the reel you opened
      //     <div>  14 videos   <- the up-next queue
      //
      // Removing the queue leaves exactly one reel and nothing to swipe to.
      //
      // Scope: reel-viewer videos are never inside <article>; feed videos
      // always are. That keeps this away from the feed, where hiding all but
      // the first video-bearing card would delete real posts.
      var MAX_CLIMB = 30;

      function reelItem(video) {
        if (video.closest('article')) return null;        // feed, not the viewer
        var node = video.parentElement, hops = 0;
        while (node && hops++ < MAX_CLIMB) {
          if (node.querySelector('a[href^="/reels/audio/"]')) return node;
          node = node.parentElement;
        }
        return null;
      }

      function containReels() {
        var items = [];
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          var item = reelItem(videos[i]);
          if (item && items.indexOf(item) === -1) items.push(item);
        }
        if (items.length < 2) return;                     // nothing to contain

        var lca = items[0];
        for (var j = 1; j < items.length; j++) {
          while (lca && !lca.contains(items[j])) lca = lca.parentElement;
        }
        if (!lca || lca === document.body || lca === document.documentElement) return;

        var keep = items[0];                              // first in document order
        var children = Array.prototype.slice.call(lca.children);
        children.forEach(function (child) {
          if (child.contains(keep)) return;
          // Only hide siblings that actually hold other reels. Without this a
          // surprising DOM shape could hide unrelated page content.
          var holdsReel = items.some(function (it) { return child.contains(it); });
          if (holdsReel) child.setAttribute('data-plainfeed-hidden', '1');
        });
      }

      // --- Premise assertions (architecture §7.6.1) --------------------
      // Each checks a CONDITIONAL, never a count: an anchor that must be
      // present, plus a claim the rule depends on. It fires only when the
      // anchor is there and the claim is false — so a quiet feed can never be
      // mistaken for a dead selector.
      function assertions() {
        var out = [];
        function add(rule, name, status, detail) {
          out.push({ rule: rule, name: name, status: status, detail: detail || '' });
        }

        // R3 — anchor: the bottom bar (holds links to / and /direct/inbox).
        //      claim: it also holds a link to /reels/.
        try {
          var home = document.querySelector('a[href="/"]');
          var inbox = document.querySelector('a[href^="/direct/inbox"]');
          var bar = null;
          if (home && inbox) {
            var n = home;
            while (n && !n.contains(inbox)) n = n.parentElement;
            bar = n;
          }
          if (!bar) {
            add('R3', 'nav bar holds /reels/ link', 'skipped', 'no nav bar on this page');
          } else {
            var link = bar.querySelector('a[href="/reels/"], a[href="/reels"]');
            add('R3', 'nav bar holds /reels/ link', link ? 'pass' : 'fail',
                link ? '' : 'bar found but no /reels/ link — href changed, tab no longer hidden');
          }
        } catch (e) { add('R3', 'nav bar holds /reels/ link', 'fail', 'threw: ' + e); }

        // R4 scope — anchor: videos outside any <article>.
        //            claim: every one of them is a reel item.
        // This is the premise that keeps containment away from the feed.
        try {
          var loose = [], all = document.querySelectorAll('video');
          for (var i = 0; i < all.length; i++) {
            if (!all[i].closest('article')) loose.push(all[i]);
          }
          if (!loose.length) {
            add('R4', 'loose videos are reel items', 'skipped', 'no videos outside <article>');
          } else {
            var unknown = loose.filter(function (v) { return !reelItem(v); }).length;
            add('R4', 'loose videos are reel items', unknown === 0 ? 'pass' : 'fail',
                unknown === 0 ? loose.length + ' checked'
                              : unknown + ' of ' + loose.length + ' lack an audio-link ancestor');
          }
        } catch (e) { add('R4', 'loose videos are reel items', 'fail', 'threw: ' + e); }

        // R4 effect — anchor: 2+ reel items present.
        //             claim: exactly one survives containment.
        try {
          var items = [], vids = document.querySelectorAll('video');
          for (var j = 0; j < vids.length; j++) {
            var it = reelItem(vids[j]);
            if (it && items.indexOf(it) === -1) items.push(it);
          }
          if (items.length < 2) {
            add('R4', 'one reel survives containment', 'skipped', items.length + ' reel item(s)');
          } else {
            var visible = items.filter(function (it) {
              return !it.closest('[data-plainfeed-hidden]');
            }).length;
            add('R4', 'one reel survives containment', visible === 1 ? 'pass' : 'fail',
                visible === 1 ? 'of ' + items.length
                              : visible + ' of ' + items.length + ' still visible — swiping may work');
          }
        } catch (e) { add('R4', 'one reel survives containment', 'fail', 'threw: ' + e); }

        // Leak — rule-independent. Catches a leak from a rule nobody asserted.
        try {
          var links = document.querySelectorAll('a[href^="/reels/"], a[href="/reels"]');
          var shown = 0;
          for (var k = 0; k < links.length; k++) {
            var r = links[k].getBoundingClientRect();
            if (r.width > 0 && r.height > 0) shown++;
          }
          add('leak', 'no visible /reels/ link', shown === 0 ? 'pass' : 'fail',
              shown === 0 ? '' : shown + ' visible');
        } catch (e) { add('leak', 'no visible /reels/ link', 'fail', 'threw: ' + e); }

        return out;
      }

      function report() {
        try {
          var h = window.webkit
            && window.webkit.messageHandlers
            && window.webkit.messageHandlers.\(messageHandler);
          if (h) h.postMessage({ assertions: assertions() });
        } catch (e) {}
      }

      var pending = null;
      function schedule() {
        if (pending) return;
        pending = setTimeout(function () {
          pending = null;
          // Isolated: a throw in one rule must not stop the others. Without
          // this, one exception kills every dynamic rule for the page's life.
          try { mono(); } catch (e) {}      // re-add if IG replaces <body>
          try { containReels(); } catch (e) {}
          try { report(); } catch (e) {}
        }, 150);
      }

      function start() {
        try { mono(); } catch (e) {}
        try { containReels(); } catch (e) {}
        try { report(); } catch (e) {}
        new MutationObserver(schedule).observe(document.documentElement, {
          childList: true, subtree: true
        });
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
      } else {
        start();
      }
    })();
    """

    private static func jsString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        let json = String(data: data, encoding: .utf8)!
        return String(json.dropFirst().dropLast())   // strip the array brackets
    }
}
