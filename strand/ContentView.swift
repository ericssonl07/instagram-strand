//
//  ContentView.swift
//  strand
//
//  Root: switches between login and the main app on auth state.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var session = SessionManager.shared

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
        .environmentObject(session)
        .task { await session.refresh() }
    }
}

#Preview {
    ContentView()
}
