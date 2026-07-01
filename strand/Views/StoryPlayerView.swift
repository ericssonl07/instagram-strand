//
//  StoryPlayerView.swift
//  strand
//
//  Fully native full-screen story/reel viewer — replaces the old constrained
//  WebView. Fetches each user's reel items from the bridge and renders images
//  and videos with IG-style segmented progress bars, tap-to-navigate,
//  hold-to-pause, and swipe-down-to-dismiss. Advances across users like IG.
//

import SwiftUI
import AVKit
import Combine

/// Identifiable wrapper so we can drive a fullScreenCover from a tapped index.
struct StoryStart: Identifiable {
    let id = UUID()
    let index: Int
}

struct StoryPlayerView: View {
    let stories: [Story]
    @Environment(\.dismiss) private var dismiss

    @State private var userIndex: Int
    @State private var items: [StoryItem] = []
    @State private var itemIndex = 0
    @State private var progress: Double = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isPaused = false
    @State private var player: AVPlayer?

    @State private var pressStart = Date()
    @State private var pressing = false

    private let tick = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    init(stories: [Story], startIndex: Int) {
        self.stories = stories
        _userIndex = State(initialValue: startIndex)
    }

    private var currentUser: Story? {
        stories.indices.contains(userIndex) ? stories[userIndex] : nil
    }
    private var currentItem: StoryItem? {
        items.indices.contains(itemIndex) ? items[itemIndex] : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                content
                overlay
            }
            .contentShape(Rectangle())
            .gesture(navGesture(width: geo.size.width))
        }
        .task(id: userIndex) { await loadUser() }
        .onReceive(tick) { _ in advanceProgress() }
        .statusBarHidden(true)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let item = currentItem {
            if item.isVideo, let player {
                PlayerLayerView(player: player).ignoresSafeArea()
            } else if let url = item.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .empty: ProgressView().tint(.white)
                    default: Image(systemName: "photo").foregroundStyle(.white)
                    }
                }
            }
        } else if isLoading {
            ProgressView().tint(.white)
        } else if loadFailed {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text("Couldn't load story")
            }
            .foregroundStyle(.white)
        }
    }

    private var overlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    GeometryReader { bar in
                        Capsule().fill(.white.opacity(0.3))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: bar.size.width * fraction(for: i))
                            }
                    }
                    .frame(height: 2.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            HStack(spacing: 10) {
                AsyncImage(url: currentUser?.author.profilePicURL) { $0.resizable().scaledToFill() }
                    placeholder: { Color.gray }
                    .frame(width: 32, height: 32).clipShape(Circle())
                Text(currentUser?.author.username ?? "")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Spacer()
        }
    }

    private func fraction(for i: Int) -> Double {
        if i < itemIndex { return 1 }
        if i == itemIndex { return progress }
        return 0
    }

    // MARK: - Timing

    private func duration(for item: StoryItem) -> Double {
        if item.isVideo {
            if let d = item.videoDuration, d > 0 { return d }
            if let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 { return d }
            return 15
        }
        return 5
    }

    private func advanceProgress() {
        guard !isPaused, !isLoading, let item = currentItem else { return }
        progress += 0.02 / duration(for: item)
        if progress >= 1 { next() }
    }

    // MARK: - Navigation

    private func next() {
        progress = 0
        if itemIndex + 1 < items.count {
            itemIndex += 1
            configureMedia()
        } else if userIndex + 1 < stories.count {
            userIndex += 1              // triggers task(id:) → loadUser()
        } else {
            dismiss()
        }
    }

    private func prev() {
        progress = 0
        if itemIndex > 0 {
            itemIndex -= 1
            configureMedia()
        } else if userIndex > 0 {
            userIndex -= 1
        }
    }

    // MARK: - Loading & media

    private func loadUser() async {
        isLoading = true
        loadFailed = false
        progress = 0
        itemIndex = 0
        teardownPlayer()
        guard let user = currentUser else { dismiss(); return }
        do {
            items = try await InstagramAPIBridge.shared.storyItems(for: user)
            isLoading = false
            if items.isEmpty {
                // Nothing viewable (private/expired) — skip forward.
                if userIndex + 1 < stories.count { userIndex += 1 } else { dismiss() }
                return
            }
            configureMedia()
        } catch {
            isLoading = false
            loadFailed = true
        }
    }

    private func configureMedia() {
        teardownPlayer()
        guard let item = currentItem, item.isVideo, let url = item.videoURL else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: url)
        player = p
        if !isPaused { p.play() }
    }

    private func teardownPlayer() {
        player?.pause()
        player = nil
    }

    // MARK: - Gesture: tap zones + hold-to-pause + swipe-down-to-dismiss

    private func navGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !pressing {
                    pressing = true
                    pressStart = Date()
                    setPaused(true)
                }
            }
            .onEnded { value in
                pressing = false
                if value.translation.height > 120 { dismiss(); return }
                setPaused(false)
                let held = Date().timeIntervalSince(pressStart)
                let isTap = held < 0.3
                    && abs(value.translation.width) < 40
                    && abs(value.translation.height) < 40
                if isTap {
                    if value.location.x < width / 3 { prev() } else { next() }
                }
            }
    }

    private func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { player?.pause() } else { player?.play() }
    }
}

/// Controls-free, aspect-fit video surface for the story player.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView(player: player) }
    func updateUIView(_ uiView: PlayerUIView, context: Context) { uiView.playerLayer.player = player }
}

final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}
