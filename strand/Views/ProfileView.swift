//
//  ProfileView.swift
//  strand
//
//  The logged-in user's own profile, rendered by IG's own UI inside a
//  constrained WebView. Username is resolved once via the bridge, then locked
//  to that profile + post permalinks. Includes logout.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var username: String?
    @State private var loadError = false

    var body: some View {
        NavigationStack {
            Group {
                if let username {
                    ConstrainedInstagramWebView(
                        initialURL: URL(string: "https://www.instagram.com/\(username)/")!,
                        allowedPaths: ["/\(username)", "/p/"]
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else if loadError {
                    ContentUnavailableView("Couldn't load profile",
                                           systemImage: "person.slash",
                                           description: Text("Pull the app back to Feed and try again."))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log Out", role: .destructive) {
                        Task { await session.logout() }
                    }
                }
            }
            .task { await loadUsername() }
        }
    }

    private func loadUsername() async {
        guard username == nil else { return }
        do {
            username = try await InstagramAPIBridge.shared.currentUsername()
        } catch {
            loadError = true
        }
    }
}
