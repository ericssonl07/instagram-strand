//
//  WebActionBridge.swift
//  strand
//
//  Performs state-changing actions (currently: likes) by driving IG's OWN web UI
//  in a hidden webview, rather than calling the private API directly. IG's raw
//  write endpoints work but invalidate our session (the request lacks integrity
//  tokens its page JS would attach). Clicking the real like button is a genuine
//  web action IG trusts, so the session survives. Trade-off: slower than the API
//  (a page load per like), and it depends on IG's DOM (the like button's
//  accessibility label) — acceptable given reliability matters more here.
//

import Foundation
import Combine
import WebKit
import UIKit

@MainActor
final class WebActionBridge: NSObject, ObservableObject {

    static let shared = WebActionBridge()

    private let webView: WKWebView
    private var didStart = false
    private var loadContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // shared cookies/login
        config.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        // Same identity as the login/API bridge so the action isn't seen as a
        // different client (see IGIdentity).
        self.webView.customUserAgent = IGIdentity.desktopUserAgent
        self.webView.navigationDelegate = self
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        attachToWindow(retries: 12)
    }

    // MARK: - Public

    /// Like/unlike `post` by clicking IG's own button on the post page.
    func like(post: Post, unlike: Bool) async throws {
        let outcome = try await runOnPost(post, js: Self.likeJS, args: ["wantUnlike": unlike])
        if outcome == "notfound" {
            throw BridgeError.httpStatus(0, "couldn't find the like button on the page")
        }
        // "clicked" or "already" ⇒ we're in the desired state.
    }

    /// Post `text` as a comment by typing into IG's own comment box and submitting.
    func comment(on post: Post, text: String) async throws {
        let outcome = try await runOnPost(post, js: Self.commentJS, args: ["text": text])
        if outcome == "notextarea" {
            throw BridgeError.httpStatus(0, "couldn't find the comment box on the page")
        }
        // "posted" (clicked Post) or "entered" (Enter fallback) ⇒ submitted.
    }

    /// Open `post`'s page in the hidden webview and run `js` (returns a status string).
    private func runOnPost(_ post: Post, js: String, args: [String: Any]) async throws -> String {
        start()
        guard let url = post.permalink else {
            throw BridgeError.httpStatus(0, "post has no shareable link to open")
        }
        await loadAndWait(url)
        let result = try? await webView.callAsyncJavaScript(js, arguments: args, in: nil, contentWorld: .page)
        guard let outcome = result as? String else { throw BridgeError.badResponse }
        return outcome
    }

    // MARK: - Injected scripts (drive IG's own UI)

    private static let likeJS = """
    const wanted = wantUnlike ? 'Unlike' : 'Like';
    const opposite = wantUnlike ? 'Like' : 'Unlike';
    for (let i = 0; i < 40; i++) {
        // Already in the desired state?
        if (document.querySelector('svg[aria-label="' + opposite + '"]')) { return 'already'; }
        const svg = document.querySelector('svg[aria-label="' + wanted + '"]');
        if (svg) {
            let el = svg;
            for (let d = 0; d < 6 && el; d++) {
                if (el.getAttribute && (el.getAttribute('role') === 'button' || el.tagName === 'BUTTON')) { break; }
                el = el.parentElement;
            }
            (el || svg).click();
            return 'clicked';
        }
        await new Promise(function (r) { setTimeout(r, 250); });
    }
    return 'notfound';
    """

    private static let commentJS = """
    function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
    function visibleTextarea() {
        const tas = document.querySelectorAll('textarea');
        for (let i = 0; i < tas.length; i++) { if (tas[i].offsetParent !== null) { return tas[i]; } }
        return tas.length ? tas[0] : null;
    }
    let ta = null;
    for (let i = 0; i < 40; i++) { ta = visibleTextarea(); if (ta) { break; } await sleep(250); }
    if (!ta) { return 'notextarea'; }
    ta.focus();
    // React controls the textarea — set the value through the native setter and
    // fire an input event so React registers it and enables the Post button.
    const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    setter.call(ta, text);
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    // Wait for the Post button to enable, then click it.
    for (let i = 0; i < 30; i++) {
        await sleep(200);
        const cands = Array.from(document.querySelectorAll('div[role="button"], button, [type="submit"]'));
        const post = cands.find(function (b) {
            const t = (b.textContent || '').trim().toLowerCase();
            return t === 'post' && !b.disabled && b.getAttribute('aria-disabled') !== 'true' && b.offsetParent !== null;
        });
        if (post) { post.click(); return 'posted'; }
    }
    // Fallback: submit with Enter.
    ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
    return 'entered';
    """

    // MARK: - Navigation helpers

    /// Navigate and wait for the page to finish (or a timeout, so we never hang).
    private func loadAndWait(_ url: URL, timeout: TimeInterval = 8) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.loadContinuation = cont
            self.webView.load(URLRequest(url: url))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.loadContinuation {   // still waiting ⇒ timed out
                    self.loadContinuation = nil
                    pending.resume()
                }
            }
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func attachToWindow(retries: Int) {
        if let window = keyWindow {
            guard webView.superview == nil else { return }
            webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            webView.alpha = 0
            webView.isUserInteractionEnabled = false
            window.addSubview(webView)
        } else if retries > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.attachToWindow(retries: retries - 1)
            }
        }
    }
}

extension WebActionBridge: WKNavigationDelegate {
    private func finishLoad() {
        if let cont = loadContinuation {
            loadContinuation = nil
            cont.resume()
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishLoad() }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad() }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishLoad() }
    }
}
