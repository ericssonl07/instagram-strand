//
//  AuthenticationView.swift
//  strand
//
//  One-time login. IG handles credentials/2FA/checkpoints in a plain WKWebView;
//  we never see a password. Success is detected by the sessionid cookie
//  appearing after a page finishes loading.
//

import SwiftUI
import WebKit

struct AuthenticationView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        LoginWebView { Task { await session.refresh() } }
            .ignoresSafeArea()
    }
}

private struct LoginWebView: UIViewRepresentable {
    let onLoggedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoggedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        // Mint the session under the SAME identity the bridge uses for writes,
        // else IG flags likes as session hijacking and logs us out.
        webView.customUserAgent = IGIdentity.desktopUserAgent
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/login/")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onLoggedIn: () -> Void
        private var fired = false
        init(_ onLoggedIn: @escaping () -> Void) { self.onLoggedIn = onLoggedIn }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                guard !fired else { return }
                let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
                let loggedIn = cookies.contains {
                    $0.name == "sessionid" && $0.domain.contains("instagram.com") && !$0.value.isEmpty
                }
                if loggedIn {
                    fired = true
                    onLoggedIn()
                }
            }
        }
    }
}
