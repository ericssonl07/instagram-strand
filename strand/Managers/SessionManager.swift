//
//  SessionManager.swift
//  strand
//
//  Observable auth-state source of truth. Logged-in ⇔ a non-empty `sessionid`
//  cookie exists on instagram.com in the shared WKWebsiteDataStore.
//

import Foundation
import Combine
import WebKit

@MainActor
final class SessionManager: ObservableObject {

    static let shared = SessionManager()

    @Published private(set) var isAuthenticated = false

    private init() {}

    func refresh() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        isAuthenticated = cookies.contains {
            $0.name == "sessionid"
            && $0.domain.contains("instagram.com")
            && !$0.value.isEmpty
        }
    }

    func logout() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
        isAuthenticated = false
    }
}
