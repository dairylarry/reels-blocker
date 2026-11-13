// Behaviour tests for the injected rules.
//
// These run the REAL script extracted from BlockingScript.swift against real
// DOM fixtures in jsdom. Nothing is reimplemented — a reimplementation would
// pass while the shipped code was broken, which is worse than no test.
//
//   ./scripts/test-dom.sh
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const ROOT = new URL('../../', import.meta.url).pathname;

function extractScript() {
  const src = readFileSync(ROOT + 'Plainfeed/Blocking/BlockingScript.swift', 'utf8');
  const m = src.match(/private static let source = """\n([\s\S]*?)\n    """/);
  if (!m) throw new Error('could not find the embedded script');
  let js = m[1]
    .replace(/\\\(messageHandler\)/g, 'plainfeed')
    .replace(/\\\(jsString\(css\)\)/g, JSON.stringify(readCSS(src)))
    .replace(/\\\\/g, '\\');
  if (js.includes('\\(')) throw new Error('unresolved Swift interpolation');
  return js;
}

function readCSS(src) {
  const m = src.match(/private static let css = """\n([\s\S]*?)\n    """/);
  return m ? m[1] : '';
}

const SCRIPT = extractScript();

/** Load a fixture at a given URL, run the rules, return the document. */
async function run(fixture, url, { rects } = {}) {
  const html = readFileSync(`${ROOT}tests/dom/fixtures/${fixture}`, 'utf8');
  const dom = new JSDOM(html, { url, runScripts: 'outside-only', pretendToBeVisual: true });
  const { window } = dom;
  const events = [];
  window.webkit = { messageHandlers: { plainfeed: { postMessage: (p) => events.push(p) } } };

  // jsdom returns a zero rect for everything. Where a rule depends on
  // geometry, the fixture supplies positions explicitly.
  if (rects) {
    window.Element.prototype.getBoundingClientRect = function () {
      const r = rects(this) || {};
      const top = r.top ?? 0, height = r.height ?? 0;
      return { top, height, bottom: top + height, left: 0, right: 0, width: r.width ?? 0 };
    };
  }

  window.eval(SCRIPT);
  await new Promise((r) => setTimeout(r, 300));   // the 150ms settle, plus slack
  return { doc: window.document, window, events };
}

let failed = 0;
function check(name, condition, detail = '') {
  const ok = !!condition;
  if (!ok) failed++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok || !detail ? '' : '  — ' + detail}`);
}

const state = (el) =>
  el?.hasAttribute('data-plainfeed-hidden') ? 'removed'
  : el?.hasAttribute('data-plainfeed-collapsed') ? 'collapsed'
  : 'untouched';

// ---------------------------------------------------------------- R7 -----
{
  const { doc } = await run('feed.html', 'https://www.instagram.com/');
  const id = (x) => doc.getElementById(x);

  check('R7 hides an injected card', state(id('injected')) === 'collapsed',
        `was ${state(id('injected'))}`);

  check('R7 collapses rather than removes it', state(id('injected')) !== 'removed',
        'display:none severs Instagram pagination and ends the feed early');

  check('R7 keeps a verified organic post', state(id('organic-verified')) === 'untouched',
        `was ${state(id('organic-verified'))}`);

  check('R7 keeps an UNVERIFIED organic post', state(id('organic-plain')) === 'untouched',
        `was ${state(id('organic-plain'))} — its header has no icon, so a text` +
        ' button before the media is the author block, not a Follow button');

  check('R7 leaves ads alone', state(id('ad')) === 'untouched',
        `was ${state(id('ad'))} — blocking ads changes the ToS risk profile`);
}

// ------------------------------------------------- R7 must skip DMs ------
{
  const { doc } = await run('dm-new.html', 'https://www.instagram.com/direct/new/');
  check('R7 does not run on /direct/**',
        state(doc.getElementById('recipient-panel')) === 'untouched',
        'hiding this panel takes the focused search field with it');
}

// ---------------------------------------------------------------- R4 -----
{
  const { doc } = await run('reel-viewer.html', 'https://www.instagram.com/direct/t/1/');
  const hiddenQueue = doc.querySelectorAll('#queue [data-plainfeed-hidden], #queue[data-plainfeed-hidden]');
  check('R4 contains the reel queue', hiddenQueue.length > 0,
        'the queue behind an opened reel is what you swipe into');
  check('R4 keeps the reel you opened',
        state(doc.getElementById('opened')) === 'untouched',
        `was ${state(doc.getElementById('opened'))}`);
}

{
  const { doc } = await run('dm-thread.html', 'https://www.instagram.com/direct/t/1/');
  check('R4 never touches a video sent in a DM',
        state(doc.getElementById('friend-video')?.parentElement) === 'untouched' &&
        state(doc.getElementById('friend-video')) === 'untouched',
        'it is outside any <article> and has no audio link — not a reel');
}

// ---------------------------------------------------------------- R8 -----
{
  // 20 posts, 740px apart. The cap is 11000px, so post 15 onward is past it.
  const { doc } = await run('long-feed.html', 'https://www.instagram.com/', {
    rects(el) {
      if (el.tagName !== 'ARTICLE') return null;
      const i = Number(el.id.split('-')[1]);
      return { top: i * 740, height: 700 };
    },
  });
  const kept = [...doc.querySelectorAll('article')].filter(
    (a) => !a.hasAttribute('data-plainfeed-hidden'));
  const removed = 20 - kept.length;

  check('R8 ends the feed at the cap', removed > 0, 'nothing was capped');
  check('R8 keeps roughly a tranche', kept.length >= 12 && kept.length <= 16,
        `kept ${kept.length}, expected about 15`);
  check('R8 keeps the first post', !doc.getElementById('post-0').hasAttribute('data-plainfeed-hidden'));
  check('R8 appends the void', !!doc.getElementById('plainfeed-void'));
  check('R8 puts a line in the void',
        /that's all/i.test(doc.getElementById('plainfeed-void')?.textContent ?? ''));
}

// -------------------------------------------------------------- route ----
{
  const { doc } = await run('feed.html', 'https://www.instagram.com/accounts/login/');
  check('DOM rules do not run on auth routes',
        [...doc.querySelectorAll('article')].every((a) => state(a) === 'untouched'),
        'breaking these locks you out of the account');
}

console.log(failed === 0 ? '\nALL BEHAVIOURS LOCKED' : `\n${failed} FAILED`);
process.exit(failed ? 1 : 0);
