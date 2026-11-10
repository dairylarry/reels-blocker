#if DEBUG
import Foundation

/// Local reproduction harness for the "keyboard appears then immediately
/// dismisses" bug in the DM recipient search.
///
/// Loads a page with the same structural shape as Instagram's new-message
/// screen — short, non-scrollable, one text input near the top — under the
/// real base URL, so the injected script's route logic behaves identically.
/// Launch with `-PlainfeedRepro 1` to use it instead of instagram.com.
///
/// This exists to test the MECHANISM without Instagram, an account, or a
/// TestFlight round trip.
enum KeyboardRepro {

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "PlainfeedRepro")
    }

    /// Base URL matters: location.pathname drives the route guard.
    static let baseURL = URL(string: "https://www.instagram.com/direct/new/")!

    static let html = """
    <!doctype html>
    <html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
      html, body { margin:0; height:100%; overflow:hidden; font:16px -apple-system; }
      .bar { padding:12px; border-bottom:1px solid #ddd; }
      input { font-size:16px; padding:10px; width:92%; border:1px solid #bbb; border-radius:8px; }
      #log { padding:10px; font:12px ui-monospace; white-space:pre-wrap; }
    </style></head>
    <body>
      <div class="bar"><input id="q" placeholder="Search names" autocomplete="off"></div>
      <div id="log">repro: short non-scrollable page, one input\\n</div>
      <script>
        var log = document.getElementById('log');
        var q = document.getElementById('q');
        function note(m) {
          log.textContent += m + '\\n';
          try {
            window.webkit.messageHandlers.plainfeed.postMessage(
              { events: [{ source: 'repro', message: m }] });
          } catch (e) {}
        }
        note('scrollHeight=' + document.documentElement.scrollHeight +
             ' innerHeight=' + window.innerHeight +
             ' scrollable=' + (document.documentElement.scrollHeight > window.innerHeight));
        q.addEventListener('focus', function () { note('INPUT FOCUSED'); });
        q.addEventListener('blur',  function () { note('INPUT BLURRED'); });
        window.visualViewport && window.visualViewport.addEventListener('resize', function () {
          note('visualViewport resize h=' + Math.round(window.visualViewport.height));
        });
        setTimeout(function () { note('calling focus()'); q.focus(); }, 1500);
        setTimeout(function () {
          note('after 4s: activeElement=' + document.activeElement.id +
               ' scrollTop=' + document.documentElement.scrollTop);
        }, 4000);
      </script>
    </body></html>
    """
}
#endif
