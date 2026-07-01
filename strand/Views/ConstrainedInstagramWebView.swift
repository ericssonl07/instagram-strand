//
//  ConstrainedInstagramWebView.swift
//  strand
//
//  Path-locked WKWebView — renders IG's own UI (DMs, profile, story player)
//  without letting the user escape into Reels/Explore. Two enforcement layers:
//  (1) navigation policy cancels disallowed main-frame nav; (2) a JS watchdog
//  catches SPA route changes and pops them back.
//

import SwiftUI
import WebKit

struct ConstrainedInstagramWebView: UIViewRepresentable {
    let initialURL: URL
    let allowedPaths: [String]
    var onBlockedNavigation: (() -> Void)? = nil
    /// Paths where the page may be viewed but vertical scrolling is disabled —
    /// e.g. a reel shared in a DM: watch it, but can't scroll into the reel feed.
    var noScrollPaths: [String] = []
    /// If non-empty, scrolling is locked on EVERY path that does NOT start with
    /// one of these. Used for Messages (only `/direct/` inbox+threads scroll) so
    /// a reel opened from a DM is locked no matter what path it lands on.
    var lockScrollExceptPaths: [String] = []
    /// Lock whenever a near-fullscreen `<video>` is on screen (a reel viewer),
    /// regardless of path — reels open as an in-place overlay that keeps the
    /// `/direct/` URL, so path rules alone can't catch them.
    var lockScrollOnFullscreenVideo: Bool = false

    // Always permit account/challenge flows so IG checks can be solved in place.
    private static let baseAllowed = ["/accounts/", "/challenge/"]
    var effectiveAllowed: [String] { allowedPaths + Self.baseAllowed }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let jsArray = "[" + effectiveAllowed.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let noScrollArray = "[" + noScrollPaths.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let scrollOnlyArray = "[" + lockScrollExceptPaths.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let watchdog = """
        (function () {
          const allowed = \(jsArray);
          const noScroll = \(noScrollArray);
          const scrollOnly = \(scrollOnlyArray);
          const detectVideo = \(lockScrollOnFullscreenVideo);
          var cachedVideo = false;   // updated on the interval (cheap hot-path)
          function starts(list, p) { return list.some(function (a) { return p.indexOf(a) === 0; }); }
          function ok(p) { return starts(allowed, p); }
          function bigVideo() {
            if (!detectVideo) return false;
            var vids = document.getElementsByTagName('video');
            var area = window.innerWidth * window.innerHeight;
            for (var i = 0; i < vids.length; i++) {
              var r = vids[i].getBoundingClientRect();
              if (r.width * r.height > area * 0.5) return true;   // near-fullscreen reel
            }
            return false;
          }
          function locked() {
            var p = location.pathname;
            if (scrollOnly.length > 0 && !starts(scrollOnly, p)) { return true; }
            if (starts(noScroll, p)) { return true; }
            return cachedVideo;
          }
          // Capture-phase + stopImmediatePropagation so IG's OWN carousel swipe
          // handler never receives the move — plain preventDefault only stops the
          // browser's native scroll, not IG's JS-driven reel advance. Taps
          // (down/up, no move) still pass through, so play/pause/close work.
          ['touchmove', 'pointermove', 'wheel'].forEach(function (ev) {
            document.addEventListener(ev, function (e) {
              if (locked()) { e.stopImmediatePropagation(); e.preventDefault(); }
            }, { passive: false, capture: true });
          });
          document.addEventListener('keydown', function (e) {
            if (locked() && ['ArrowDown','ArrowUp','PageDown','PageUp',' '].indexOf(e.key) !== -1) {
              e.stopImmediatePropagation(); e.preventDefault();
            }
          }, { capture: true });
          setInterval(function () {
            try {
              if (!ok(location.pathname)) { history.back(); }
              cachedVideo = bigVideo();
              var isLocked = locked();
              var style = document.getElementById('strand-scroll-lock');
              if (isLocked && !style) {
                style = document.createElement('style');
                style.id = 'strand-scroll-lock';
                style.textContent =
                  'html,body{overflow:hidden!important;height:100%!important;}' +
                  '*{touch-action:none!important;overscroll-behavior:none!important;}';
                (document.head || document.documentElement).appendChild(style);
              } else if (!isLocked && style) {
                style.remove();
              }
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.strandScroll) {
                window.webkit.messageHandlers.strandScroll.postMessage(isLocked);
              }
            } catch (e) {}
          }, 250);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: watchdog, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        if !noScrollPaths.isEmpty || !lockScrollExceptPaths.isEmpty || lockScrollOnFullscreenVideo {
            config.userContentController.add(context.coordinator, name: "strandScroll")
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: ConstrainedInstagramWebView
        weak var webView: WKWebView?
        init(_ parent: ConstrainedInstagramWebView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "strandScroll", let locked = message.body as? Bool else { return }
            webView?.scrollView.isScrollEnabled = !locked
            webView?.scrollView.bounces = !locked
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame ?? true,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            let host = url.host ?? ""
            // Allow non-IG hosts (login redirects to facebook, CDNs, etc.).
            guard host.contains("instagram.com") else { decisionHandler(.allow); return }

            if parent.effectiveAllowed.contains(where: { url.path.hasPrefix($0) }) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if let cb = parent.onBlockedNavigation {
                    DispatchQueue.main.async { cb() }
                }
            }
        }
    }
}
