//
//  Post.swift
//  strand
//
//  Domain models + the raw DTOs decoded from Instagram's private JSON API.
//  These ARE the app's "fixed, predictable format" — no ML/LLM in the runtime path.
//

import Foundation

// MARK: - Domain models (used by the UI)

struct User: Identifiable, Hashable {
    let id: String
    let username: String
    let fullName: String
    let profilePicURL: URL?
    let isVerified: Bool
}

struct Post: Identifiable, Hashable {
    let id: String
    let author: User
    let imageURLs: [URL]      // one, or many for carousels
    let caption: String?
    let likeCount: Int
    let hasLiked: Bool
    let takenAt: Date
    let code: String?         // shortcode for /p/{code}/

    /// Public web permalink — used for native sharing.
    var permalink: URL? { code.flatMap { URL(string: "https://www.instagram.com/p/\($0)/") } }
}

struct Story: Identifiable, Hashable {
    let id: String
    let author: User
    let thumbnailURL: URL?
    let hasUnseen: Bool
}

/// One image/video segment inside a user's story reel.
struct StoryItem: Identifiable, Hashable {
    let id: String
    let imageURL: URL?
    let videoURL: URL?
    let videoDuration: Double?
    let takenAt: Date
    var isVideo: Bool { videoURL != nil }
}

struct Comment: Identifiable, Hashable {
    let id: String
    let user: User
    let text: String
    let createdAt: Date
}

struct FeedPage {
    let posts: [Post]
    let nextMaxId: String?
    let moreAvailable: Bool
}

// MARK: - Decoding helper

/// IG returns some IDs as numbers and others as strings. Normalize to String.
struct FlexibleString: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(Int(d)) }
        else { value = "" }
    }
}

// MARK: - Raw API DTOs (a deliberately small subset of IG's JSON)

struct IGTimelineResponse: Decodable {
    let feedItems: [IGFeedItem]?
    let nextMaxId: String?
    let moreAvailable: Bool?
    enum CodingKeys: String, CodingKey {
        case feedItems = "feed_items"
        case nextMaxId = "next_max_id"
        case moreAvailable = "more_available"
    }
}

struct IGFeedItem: Decodable {
    let mediaOrAd: IGMedia?
    enum CodingKeys: String, CodingKey { case mediaOrAd = "media_or_ad" }
}

struct IGMedia: Decodable {
    let id: String?
    let code: String?
    let takenAt: Double?
    let mediaType: Int?
    let user: IGUser?
    let caption: IGCaption?
    let likeCount: Int?
    let hasLiked: Bool?
    let imageVersions2: IGImageVersions?
    let carouselMedia: [IGCarouselItem]?
    let injected: IGInjected?   // presence ⇒ ad / suggested — skip
    let adId: String?           // presence ⇒ ad — skip

    enum CodingKeys: String, CodingKey {
        case id, code, user, caption, injected
        case takenAt = "taken_at"
        case mediaType = "media_type"
        case likeCount = "like_count"
        case hasLiked = "has_liked"
        case imageVersions2 = "image_versions2"
        case carouselMedia = "carousel_media"
        case adId = "ad_id"
    }
}

struct IGInjected: Decodable {}   // empty: only its presence matters
struct IGCaption: Decodable { let text: String? }
struct IGImageVersions: Decodable { let candidates: [IGCandidate]? }
struct IGCandidate: Decodable { let url: String?; let width: Int?; let height: Int? }
struct IGCarouselItem: Decodable {
    let imageVersions2: IGImageVersions?
    enum CodingKeys: String, CodingKey { case imageVersions2 = "image_versions2" }
}

struct IGUser: Decodable {
    let pk: FlexibleString?
    let username: String?
    let fullName: String?
    let profilePicUrl: String?
    let isVerified: Bool?
    enum CodingKeys: String, CodingKey {
        case pk, username
        case fullName = "full_name"
        case profilePicUrl = "profile_pic_url"
        case isVerified = "is_verified"
    }
}

struct IGReelsTrayResponse: Decodable {
    let tray: [IGTrayReel]?
}

struct IGTrayReel: Decodable {
    let id: FlexibleString?
    let user: IGUser?
    let seen: Double?
    let latestReelMedia: Double?
    enum CodingKeys: String, CodingKey {
        case id, user, seen
        case latestReelMedia = "latest_reel_media"
    }
}

struct IGCurrentUserResponse: Decodable { let user: IGUser? }

struct IGCommentsResponse: Decodable { let comments: [IGComment]? }

struct IGComment: Decodable {
    let pk: FlexibleString?
    let text: String?
    let user: IGUser?
    let createdAt: Double?
    let createdTime: Double?
    enum CodingKeys: String, CodingKey {
        case pk, text, user
        case createdAt = "created_at"
        case createdTime = "created_time"
    }
}

struct IGUserStoryResponse: Decodable { let reel: IGReel? }
struct IGReel: Decodable { let items: [IGStoryItem]? }

struct IGStoryItem: Decodable {
    let pk: FlexibleString?
    let id: String?
    let mediaType: Int?
    let takenAt: Double?
    let imageVersions2: IGImageVersions?
    let videoVersions: [IGVideoVersion]?
    let videoDuration: Double?
    enum CodingKeys: String, CodingKey {
        case pk, id
        case mediaType = "media_type"
        case takenAt = "taken_at"
        case imageVersions2 = "image_versions2"
        case videoVersions = "video_versions"
        case videoDuration = "video_duration"
    }
}

struct IGVideoVersion: Decodable { let url: String? }

// MARK: - Raw → domain mapping

extension User {
    init(raw: IGUser) {
        self.id = raw.pk?.value ?? raw.username ?? UUID().uuidString
        self.username = raw.username ?? "unknown"
        self.fullName = raw.fullName ?? ""
        self.profilePicURL = raw.profilePicUrl.flatMap(URL.init(string:))
        self.isVerified = raw.isVerified ?? false
    }
}

extension Post {
    /// Returns nil for anything that isn't a renderable image/video post
    /// (skips suggested-user blocks, end-of-feed markers, ads).
    init?(raw: IGMedia) {
        guard raw.injected == nil, raw.adId == nil,
              let id = raw.id, let rawUser = raw.user else { return nil }

        var urls: [URL] = []
        if let carousel = raw.carouselMedia, !carousel.isEmpty {
            urls = carousel.compactMap { $0.imageVersions2?.candidates?.first?.url }
                           .compactMap(URL.init(string:))
        } else if let first = raw.imageVersions2?.candidates?.first?.url,
                  let url = URL(string: first) {
            urls = [url]
        }
        guard !urls.isEmpty else { return nil }

        self.id = id
        self.author = User(raw: rawUser)
        self.imageURLs = urls
        self.caption = raw.caption?.text
        self.likeCount = raw.likeCount ?? 0
        self.hasLiked = raw.hasLiked ?? false
        self.takenAt = Date(timeIntervalSince1970: raw.takenAt ?? 0)
        self.code = raw.code
    }
}

extension Story {
    init?(raw: IGTrayReel) {
        guard let rawUser = raw.user else { return nil }
        let author = User(raw: rawUser)
        self.id = raw.id?.value ?? author.id
        self.author = author
        self.thumbnailURL = author.profilePicURL
        self.hasUnseen = (raw.latestReelMedia ?? 0) > (raw.seen ?? 0)
    }
}

extension StoryItem {
    init?(raw: IGStoryItem) {
        guard let id = raw.pk?.value ?? raw.id else { return nil }
        let image = raw.imageVersions2?.candidates?.first?.url.flatMap(URL.init(string:))
        let video = raw.videoVersions?.first?.url.flatMap(URL.init(string:))
        guard image != nil || video != nil else { return nil }
        self.id = id
        self.imageURL = image
        self.videoURL = video
        self.videoDuration = raw.videoDuration
        self.takenAt = Date(timeIntervalSince1970: raw.takenAt ?? 0)
    }
}

extension Comment {
    init?(raw: IGComment) {
        guard let text = raw.text, let rawUser = raw.user else { return nil }
        self.id = raw.pk?.value ?? UUID().uuidString
        self.user = User(raw: rawUser)
        self.text = text
        self.createdAt = Date(timeIntervalSince1970: raw.createdAt ?? raw.createdTime ?? 0)
    }
}
