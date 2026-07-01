//
//  StoriesView.swift
//  strand
//
//  Native stories tray. Tapping a bubble opens the story in a constrained
//  web player (/stories/ only) that auto-dismisses when IG would otherwise
//  fall back to the home feed.
//

import SwiftUI
import Combine

@MainActor
final class StoriesViewModel: ObservableObject {
    @Published private(set) var stories: [Story] = []

    func load() async {
        guard stories.isEmpty else { return }
        stories = (try? await InstagramAPIBridge.shared.storiesTray()) ?? []
    }
}

struct StoriesView: View {
    @StateObject private var model = StoriesViewModel()
    @State private var start: StoryStart?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(model.stories.enumerated()), id: \.element.id) { index, story in
                    Button { start = StoryStart(index: index) } label: { StoryBubble(story: story) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .task { await model.load() }
        .fullScreenCover(item: $start) { start in
            StoryPlayerView(stories: model.stories, startIndex: start.index)
        }
    }
}

private struct StoryBubble: View {
    let story: Story

    var body: some View {
        VStack(spacing: 4) {
            AsyncImage(url: story.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(.tertiarySystemFill)
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        story.hasUnseen
                            ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink, .orange],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.clear),
                        lineWidth: 2.5
                    )
                    .padding(-3)
            )
            Text(story.author.username)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 64)
        }
    }
}

