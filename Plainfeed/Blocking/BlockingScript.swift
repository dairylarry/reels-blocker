import WebKit

enum BlockingScript {

    /// Name the injected script posts assertion results to.
    static let messageHandler = "plainfeed"


    /// Injected at documentStart so the CSS applies before first paint and the
    /// history hooks are installed before Instagram's router runs.
    static func userScript() -> WKUserScript {
        var prelude = ""
        if UserDefaults.standard.bool(forKey: "PlainfeedNoMono") {
            prelude += "window.__plainfeedNoMono = true;\n"
        }
        if UserDefaults.standard.bool(forKey: "PlainfeedNoR7") {
            prelude += "window.__plainfeedNoR7 = true;\n"
        }
        return WKUserScript(source: prelude + source,
                            injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Href-based only — identical in every language (§5.1).
    private static let css = """
    a[href="/reels/"], a[href="/reels"] { display: none !important; }

    /* Two hide mechanisms, deliberately different.

       COLLAPSED — suppress without stopping the feed. Instagram's load-more
       trigger depends on cards participating in layout and the intersection
       tree, so `display: none` on a card severs it and the feed dies early.
       A 1px sliver stays in the flow and keeps the observer alive. */
    [data-plainfeed-collapsed] {
      height: 1px !important;
      min-height: 0 !important;
      overflow: hidden !important;
      opacity: 0 !important;
      pointer-events: none !important;
    }

    /* REMOVED — stop the feed on purpose. Used past the tranche limit, where
       severing the loader is exactly the intent. */
    [data-plainfeed-hidden] { display: none !important; }

    /* The feed ends in blank space, with a quiet line centred in it. The text
       lives INSIDE the void rather than floating over the content, so you come
       across it by scrolling into the blank instead of having it cover the
       last post.

       No background is set, so it inherits the page's own and stays correct in
       dark mode. The colour is a mid grey that reads on either. */
    #plainfeed-void {
      height: 150vh;
      pointer-events: none;
      display: flex;
      align-items: center;
      justify-content: center;
      font: 500 17px/1.4 -apple-system, system-ui, sans-serif;
      letter-spacing: 0.2px;
      color: #8e8e8e;
    }

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
        if (window.__plainfeedNoMono) return;   // A/B switch for diagnosis
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

        // R4 scope — anchor: at least one reel item detected.
        //            claim: no reel item encloses a feed card.
        //
        // The previous version asserted that EVERY video outside an <article>
        // is a reel item. That premise was simply false — a video someone
        // sends you in a DM is outside any article and is not a reel — so it
        // failed on normal use 27 times over a month. What actually matters is
        // narrower: containment must never grab something containing feed
        // cards, because that is how it would start eating the feed.
        try {
          var items = [], vids = document.querySelectorAll('video');
          for (var i = 0; i < vids.length; i++) {
            var ri = reelItem(vids[i]);
            if (ri && items.indexOf(ri) === -1) items.push(ri);
          }
          if (!items.length) {
            add('R4', 'reel items exclude feed cards', 'skipped', 'no reel items on this page');
          } else {
            var enclosing = items.filter(function (it) { return !!it.querySelector('article'); }).length;
            add('R4', 'reel items exclude feed cards', enclosing === 0 ? 'pass' : 'fail',
                enclosing === 0 ? items.length + ' item(s) checked'
                                : enclosing + ' reel item(s) enclose a feed card — containment could hide real posts');
          }
        } catch (e) { add('R4', 'reel items exclude feed cards', 'fail', 'threw: ' + e); }

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
              return !it.closest('[data-plainfeed-hidden], [data-plainfeed-collapsed]');
            }).length;
            add('R4', 'one reel survives containment', visible === 1 ? 'pass' : 'fail',
                visible === 1 ? 'of ' + items.length
                              : visible + ' of ' + items.length + ' still visible — swiping may work');
          }
        } catch (e) { add('R4', 'one reel survives containment', 'fail', 'threw: ' + e); }

        // Leak — rule-independent. Catches Reels coming back by a route no
        // rule anticipated.
        //
        // Deliberately EXACT, not a prefix match. `a[href^="/reels/"]` also
        // matches two things that are legitimately on screen:
        //   /reels/<shortcode>/   a followed account's video post in the feed,
        //                         which we keep on purpose (§4.4)
        //   /reels/audio/<id>/    audio attribution inside a reel opened from
        //                         a DM, which we allow on purpose (R2)
        // Matching those turned the banner amber during normal use. An alarm
        // that cries wolf is worse than no alarm.
        try {
          var links = document.querySelectorAll('a[href="/reels/"], a[href="/reels"]');
          var shown = 0;
          for (var k = 0; k < links.length; k++) {
            var r = links[k].getBoundingClientRect();
            if (r.width > 0 && r.height > 0) shown++;
          }
          add('screen', 'no Reels entry point visible', shown === 0 ? 'pass' : 'fail',
              shown === 0 ? '' : shown + ' visible — R3 is not hiding the tab');
        } catch (e) { add('screen', 'no Reels entry point visible', 'fail', 'threw: ' + e); }

        // R7 — anchor: feed cards present on a route where DOM rules run.
        //      claim: they expose a [role=presentation] media block, which is
        //      how the rule locates the end of a card's header.
        // Detail carries what R7 actually did, so its behaviour is visible.
        try {
          if (!domRulesAllowedHere()) {
            add('R7', 'feed cards expose a media marker', 'skipped', 'DOM rules off on this route');
          } else if (location.pathname !== '/') {
            // The premise only matters on the home feed. <article> appears on
            // other pages — the logged-out landing page has one with no
            // [role=presentation] — and asserting there produced a false
            // alarm.
            add('R7', 'feed cards expose a media marker', 'skipped', 'not the home feed');
          } else {
            var arts = document.querySelectorAll('article');
            if (document.readyState !== 'complete') {
              // Mid-load the feed has <article> elements whose media blocks
              // have not rendered yet. Asserting then produced a transient
              // false alarm.
              add('R7', 'feed cards expose a media marker', 'skipped', 'page still loading');
            } else if (!arts.length) {
              add('R7', 'feed cards expose a media marker', 'skipped', 'no feed cards — ' + suggestedState);
            } else {
              var withMedia = 0;
              for (var m = 0; m < arts.length; m++) {
                if (arts[m].querySelector('[role="presentation"]')) withMedia++;
              }
              add('R7', 'feed cards expose a media marker', withMedia > 0 ? 'pass' : 'fail',
                  withMedia > 0 ? withMedia + ' of ' + arts.length + ' — ' + suggestedState
                                : 'no card exposes [role=presentation] — rule cannot locate headers');
            }
          }
        } catch (e) { add('R7', 'feed cards expose a media marker', 'fail', 'threw: ' + e); }

        // R8 — anchor: on the home feed.
        //      claim: scroll position is at or below the cap.
        try {
          if (!onFeed()) {
            add('R8', 'feed within scroll cap', 'skipped', 'not the home feed');
          } else {
            // Scrolling past the limit is expected now — that is the void.
            // The claim is that no VISIBLE post lives beyond it.
            var y2 = window.scrollY, beyond = 0, visible = 0;
            var all = document.querySelectorAll('article');
            for (var q = 0; q < all.length; q++) {
              var el = all[q];
              if (el.hasAttribute('data-plainfeed-hidden')) continue;
              if (el.hasAttribute('data-plainfeed-collapsed')) continue;
              visible++;
              if (el.getBoundingClientRect().top + y2 >= SCROLL_LIMIT) beyond++;
            }
            add('R8', 'no posts past the cap', beyond === 0 ? 'pass' : 'fail',
                visible + ' posts, ' + beyond + ' past ' + SCROLL_LIMIT +
                (capped ? ' — ended' : ' — filling'));
          }
        } catch (e) { add('R8', 'feed within scroll cap', 'fail', 'threw: ' + e); }

        return out;
      }

      function send(payload) {
        try {
          var h = window.webkit
            && window.webkit.messageHandlers
            && window.webkit.messageHandlers.\(messageHandler);
          if (h) h.postMessage(payload);
        } catch (e) {}
      }

      function report() { send({ assertions: assertions() }); }

      // --- R7: suggested (injected) feed cards -------------------------
      // The home feed mixes posts from accounts you follow with algorithmically
      // injected ones. The injected cards are the infinite-scroll hole, and
      // they are also where reels arrive in the feed — so this single rule is
      // the whole home-feed strategy (§4.4).
      //
      // Language-invariant discriminator, verified against a real capture:
      // every button in an organic card's header contains an <svg> icon (More
      // options, Like, Comment). The Follow button on an injected card is the
      // only one with TEXT and NO ICON. So:
      //
      //   hide an <article> containing a [role=button] that
      //     (a) appears BEFORE the card's [role=presentation] media block,
      //     (b) contains no <svg>, and
      //     (c) has non-empty text.
      //
      // No strings, so it behaves identically in English, Spanish and Mandarin.
      // NOTE: ads are NOT matched — their CTAs sit below the media and carry a
      // chevron <svg>. Leaving ads alone is deliberate (§7.10).
      var OVERMATCH_RATIO = 0.7;

      // RULES.md invariant: no rule may hide anything under /direct/** that is
      // not a queued reel. R4 enforces that by construction; R7 needs an
      // explicit guard, because it matches on <article> and would happily hide
      // one on the new-message screen — taking the focused recipient search
      // field with it, which drops the keyboard.
      var NO_DOM_RULES = new RegExp('^/(direct|accounts|challenge|two_factor|oauth)/');

      function domRulesAllowedHere() {
        try { return !NO_DOM_RULES.test(location.pathname); } catch (e) { return false; }
      }

      // Last R7 outcome, surfaced in its assertion so the rule's behaviour is
      // visible without flooding the event log on every mutation.
      var suggestedState = 'not run';

      function isInjected(article) {
        var media = article.querySelector('[role="presentation"]');
        if (!media) return false;                  // can't locate the header
        var buttons = article.querySelectorAll('[role="button"]');
        for (var i = 0; i < buttons.length; i++) {
          var b = buttons[i];
          // keep only buttons positioned before the media block
          var mediaFollows = b.compareDocumentPosition(media) & Node.DOCUMENT_POSITION_FOLLOWING;
          if (!mediaFollows) continue;
          if (b.querySelector('svg')) continue;    // icon button, not Follow
          // The author block is also a [role=button] holding text, and on an
          // UNVERIFIED account it carries no icon either — so without this it
          // matches and the post gets hidden. It always contains the profile
          // link; a Follow button never does. Caught by tests/dom, after every
          // organic card in the captured feed happened to be verified.
          if (b.querySelector('a, [role="link"]')) continue;
          if (!(b.textContent || '').trim()) continue;
          return true;
        }
        return false;
      }

      function hideSuggested() {
        if (window.__plainfeedNoR7) { suggestedState = 'disabled for diagnosis'; return; }
        if (!domRulesAllowedHere()) { suggestedState = 'skipped on this route'; return; }
        var articles = document.querySelectorAll('article');
        if (!articles.length) { suggestedState = 'no feed cards'; return; }
        var matches = [];
        for (var i = 0; i < articles.length; i++) {
          if (isInjected(articles[i])) matches.push(articles[i]);
        }
        // Over-match guard: hiding most of the feed means the discriminator
        // broke, not that the feed is all suggestions. Report, don't hide.
        if (articles.length >= 3 && matches.length / articles.length > OVERMATCH_RATIO) {
          suggestedState = 'over-match guard tripped: ' + matches.length + ' of ' + articles.length;
          send({ events: [{ source: 'R7', message: 'over-match guard: ' + matches.length +
                 ' of ' + articles.length + ' feed cards matched — not hiding' }] });
          return;
        }
        matches.forEach(function (a) { a.setAttribute('data-plainfeed-collapsed', '1'); });
        suggestedState = 'hid ' + matches.length + ' of ' + articles.length;
      }

      // Rule exceptions used to be swallowed by empty catch blocks, so a rule
      // that threw on every pass was completely invisible. Report each one,
      // but only the first time per rule per page — otherwise a rule throwing
      // on every mutation would fill the 50-entry log in seconds.
      var reportedThrows = {};

      function runRule(name, fn) {
        try {
          fn();
        } catch (e) {
          if (!reportedThrows[name]) {
            reportedThrows[name] = true;
            send({ events: [{ source: name, message: 'threw: ' + e }] });
          }
        }
      }

      // Focus-loss detection. If the element the user is typing into ends up
      // inside something we hid, we caused the keyboard to drop. This is
      // deliberately narrow — it only fires when OUR marker is on an ancestor,
      // so Instagram moving focus on its own can never trigger it.
      function focusedEditable() {
        var el = document.activeElement;
        if (!el) return null;
        var tag = el.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || el.isContentEditable) return el;
        return null;
      }

      function checkFocusStolen(before) {
        if (!before) return;
        try {
          if (before.closest('[data-plainfeed-hidden]')) {
            send({ events: [{ source: 'focus', message:
              'a rule hid the focused ' + before.tagName.toLowerCase() +
              ' on ' + location.pathname + ' — this drops the keyboard' }] });
          } else if (!before.isConnected) {
            send({ events: [{ source: 'focus', message:
              'focused ' + before.tagName.toLowerCase() + ' left the DOM on ' +
              location.pathname + ' (not hidden by us)' }] });
          }
        } catch (e) {}
      }

      // --- focus instrumentation --------------------------------------
      // Diagnosing a keyboard that appears and immediately dismisses. The
      // question this answers: does the PAGE lose focus (a blur fires), or
      // does the keyboard go while focus is retained? The first means
      // something in the DOM dropped it; the second means the native side
      // resigned first responder and the page never knew.
      //
      // Only blurs within 2s of focus are logged — the immediate-dismissal
      // signature — so normal typing can't fill the log.
      var focusAt = 0, focusPath = '', focusTag = '';

      function isEditable(el) {
        if (!el) return false;
        return el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable;
      }

      document.addEventListener('focusin', function (e) {
        if (!isEditable(e.target)) return;
        focusAt = Date.now();
        focusPath = location.pathname;
        focusTag = e.target.tagName.toLowerCase();
      }, true);

      document.addEventListener('focusout', function (e) {
        if (!isEditable(e.target) || !focusAt) return;
        var held = Date.now() - focusAt;
        focusAt = 0;
        if (held > 2000) return;                 // ordinary end of typing
        var el = e.target;
        var why = [];
        try {
          if (!el.isConnected) why.push('left the DOM');
          if (el.closest && el.closest('[data-plainfeed-hidden]')) why.push('inside something we hid');
          var r = el.getBoundingClientRect();
          if (!r.width || !r.height) why.push('zero-sized');
          if (location.pathname !== focusPath) why.push('url changed to ' + location.pathname);
          if (document.activeElement && document.activeElement !== el) {
            why.push('focus moved to ' + document.activeElement.tagName.toLowerCase());
          }
        } catch (err) { why.push('probe threw: ' + err); }
        send({ events: [{ source: 'focus', message:
          'BLUR after ' + held + 'ms on ' + focusPath + ' (' + focusTag + ') — ' +
          (why.length ? why.join('; ') : 'no DOM cause found; element still focusable') }] });
      }, true);

      // --- blank-feed diagnosis ----------------------------------------
      // Logs ONLY the problem state: scrolled down with no feed card
      // intersecting the viewport. Self-limiting, so it cannot flood the log.
      // Distinguishes "cards are here but not painting" from "the page is tall
      // and genuinely empty at this offset".
      var lastBlankLog = 0;

      function checkBlankViewport() {
        try {
          var y = window.scrollY, h = window.innerHeight;
          if (y < h) return;                       // near the top, not the case
          var arts = document.querySelectorAll('article');
          if (!arts.length) return;
          var inView = 0, tops = [], hidden = 0;
          for (var i = 0; i < arts.length; i++) {
            var r = arts[i].getBoundingClientRect();
            tops.push(Math.round(r.top + y));
            if (r.bottom > 0 && r.top < h) inView++;
            if (arts[i].hasAttribute('data-plainfeed-hidden')) hidden++;
          }
          if (inView > 0) return;                  // something is on screen
          // Reaching the end of a feed that is still loading is normal and
          // was firing constantly. A real void is a large reserved gap below
          // the last card — more than two viewports of nothing.
          var maxBottom = 0;
          for (var j = 0; j < arts.length; j++) {
            var rb = arts[j].getBoundingClientRect();
            if (rb.height > 0) maxBottom = Math.max(maxBottom, rb.bottom + y);
          }
          if (document.documentElement.scrollHeight - maxBottom < h * 2) return;
          var now = Date.now();
          if (now - lastBlankLog < 4000) return;
          lastBlankLog = now;
          tops.sort(function (a, b) { return a - b; });
          send({ events: [{ source: 'blank', message:
            'no card in viewport — scrollY=' + Math.round(y) +
            ' innerH=' + h +
            ' scrollH=' + document.documentElement.scrollHeight +
            ' cards=' + arts.length + ' (hidden ' + hidden + ')' +
            ' cardTops=[' + tops.slice(0, 3).join(',') + ' … ' + tops.slice(-2).join(',') + ']' }] });
        } catch (e) {}
      }

      var scrollTimer = null;
      window.addEventListener('scroll', function () {
        if (scrollTimer) return;
        scrollTimer = setTimeout(function () {
          scrollTimer = null;
          checkBlankViewport();
        }, 600);
      }, { passive: true });

      // --- R8: the feed is finite --------------------------------------
      // Capped by SCROLL DEPTH, not by counting cards.
      //
      // Instagram virtualises the feed: it keeps a sliding window of ~9
      // <article> elements in the DOM and recycles them, so counting cards
      // can never tell you how many posts you have passed — measured at
      // scrollY=22180 with 9 cards present. Scroll position is a browser
      // primitive and owes nothing to Instagram's markup, which puts this in
      // the durable layer alongside the route rules.
      //
      // Approximate by design: posts run ~740px, so the limit is "about 15".
      // Taller posts mean fewer, which is the correct direction to fail.
      //
      // Side effect: the cap sits well below the height Instagram reserves but
      // never renders, so the blank region at ~22000px becomes unreachable.
      var SCROLL_LIMIT = 11000;
      var capped = false;

      function onFeed() {
        try { return location.pathname === '/'; } catch (e) { return false; }
      }

      function addVoid() {
        if (document.getElementById('plainfeed-void') || !document.body) return;
        var v = document.createElement('div');
        v.id = 'plainfeed-void';
        v.setAttribute('aria-hidden', 'true');
        v.textContent = "That's all.";
        document.body.appendChild(v);
      }

      // Hide every post past the limit, then everything trailing it inside the
      // feed container — Instagram's spacers and loading glimmers, which would
      // otherwise leave thousands of pixels of reserved height. What remains
      // is the void we append: about one and a half screens of blank, then the
      // document simply ends.
      function capFeed() {
        if (!onFeed()) return;
        var arts = document.querySelectorAll('article');
        if (!arts.length) return;

        var y = window.scrollY, last = null, cut = false;
        for (var i = 0; i < arts.length; i++) {
          var a = arts[i];
          if (a.hasAttribute('data-plainfeed-collapsed')) continue;   // R7
          if (a.hasAttribute('data-plainfeed-hidden')) { cut = true; continue; }
          var top = a.getBoundingClientRect().top + y;
          if (top < SCROLL_LIMIT) { last = a; continue; }
          a.setAttribute('data-plainfeed-hidden', '1');
          cut = true;
        }
        if (!cut || !last) return;

        var container = last.parentElement;
        while (container && container.querySelectorAll('article').length < 2) {
          container = container.parentElement;
        }
        if (container) {
          var seen = false;
          Array.prototype.slice.call(container.children).forEach(function (child) {
            if (child.contains(last)) { seen = true; return; }
            if (seen) child.setAttribute('data-plainfeed-hidden', '1');
          });
        }
        addVoid();

        if (capped) return;
        capped = true;
        send({ events: [{ source: 'R8', message:
          'feed ended past ' + SCROLL_LIMIT + 'px (~15 posts)' }] });
      }

      window.addEventListener('scroll', function () { capFeed(); }, { passive: true });

      var pending = null;
      function schedule() {
        if (pending) return;
        pending = setTimeout(function () {
          pending = null;
          var focusBefore = focusedEditable();
          runRule('mono', mono);            // re-add if IG replaces <body>
          runRule('R4', containReels);
          runRule('R7', hideSuggested);
          runRule('R8', capFeed);
          checkFocusStolen(focusBefore);
          runRule('report', report);
        }, 150);
      }

      function start() {
        runRule('mono', mono);
        runRule('R4', containReels);
        runRule('R7', hideSuggested);
        runRule('R8', capFeed);
        runRule('report', report);
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
