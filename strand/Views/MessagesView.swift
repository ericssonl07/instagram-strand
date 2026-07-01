//
//  MessagesView.swift
//  strand
//
//  Direct messages, rendered by IG's own UI inside a constrained WebView locked
//  to /direct/. Deliberately not rebuilt natively — the maintainability escape
//  hatch.
//

import SwiftUI

struct MessagesView: View {
    var body: some View {
        ConstrainedInstagramWebView(
            initialURL: URL(string: "https://www.instagram.com/direct/inbox/")!,
            // Allow a reel shared in a thread to open (/reel/ or /reels/) …
            allowedPaths: ["/direct/", "/reel/", "/reels/"],
            // … but only the inbox/threads (/direct/) may scroll, AND lock
            // whenever a near-fullscreen video (a reel) is on screen — reels open
            // as an in-place overlay that keeps the /direct/ URL, and their
            // swipe-to-next is IG's own carousel JS, so we must catch it by
            // content and stop the event before IG's handler sees it.
            lockScrollExceptPaths: ["/direct/"],
            lockScrollOnFullscreenVideo: true
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
