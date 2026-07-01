//
//  MainTabView.swift
//  strand
//
//  Root tab shell shown once authenticated. Feed (+ Stories) is native;
//  Messages and Profile are constrained web surfaces. No Reels/Explore tab —
//  the distraction removal is structural.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "house") }
            MessagesView()
                .tabItem { Label("Messages", systemImage: "paperplane") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }
        }
        .onAppear { InstagramAPIBridge.shared.start() }
    }
}
