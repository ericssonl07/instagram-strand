# Strand

Instagram's default experience has become a tangled web, engineered to maximize your time-in-app via algorithmic recommendation surfaces and endless discovery feeds. Meta brought us Instagram and Threads- an infinite spool of content designed to keep people scrolling.

Introducing Strand.

A single, deliberate strand pulled free of noise- one single, chronological feed of the people you follow. No algorithmic recommendations. No suggested posts. No Explore tab. No notification badges designed to interrupt you. *No dopamine hijacking.* Strand is a minimalist, native iOS client that shows you exactly what the people you care about actually posted- nothing more, nothing less. By cutting away the engagement bait that has vitiated social media's original mission, it restores the true focus of social media: genuine connection with the people you care about.

Fast. Calm. Deliberate.

## 🛠 How it works

Strand isn't a `WKWebView` pointed at instagram.com with some CSS hidden. It's a hybrid architecture:

- **Reads (feed, stories, comments, profile data)** go through a hidden, logged-in `WKWebView` that executes `fetch()` calls against Instagram's own private API from within IG's page origin- real cookies, real CSRF tokens, real anti-abuse headers, captured live from the authenticated session. The results are parsed into native Swift models and rendered entirely in SwiftUI.
- **Writes (likes, comments)** deliberately avoid raw API calls, which lack the integrity tokens needed to survive Instagram's abuse detection. Instead, a second hidden webview drives Instagram's real UI directly- clicking the actual like button, typing into the actual comment box- so the write looks (and is) identical to using instagram.com.
- **Login, DMs, and your own profile** use a third pattern: a path-locked, visible `WKWebView` showing Instagram's genuine UI, restricted with a JS sentry to only the routes it's meant for (e.g. `/direct/` for messages), and hardened to block things like the Reels carousel from sneaking in through an inbox.

The result: no scraping fragility, no fabricated fingerprints, and no visible "this is secretly a browser" seams- while every pixel you interact with day-to-day (feed, stories, comments) is fully native.

## ✨ Features

| Area | Status | Notes |
|---|---|---|
| Feed | Native, complete | Chronological, cursor-paginated, like/comment/share, no algorithmic ranking or injected ads. |
| Stories | Native, complete | Horizontal tray + fullscreen player (progress bars, tap-to-advance, hold-to-pause, swipe-to-dismiss, video via AVKit). |
| Comments | Native, nonfunctional (todo) | Currently fails to find the underlying text field and does not send a comment. Fails gracefully. |
| Messages | Functional | Constrained webview onto Instagram's real DM UI. Reels sent from DMs may be viewed without the ability to scroll beyond the initial page. |
| Profile | To be implemented | Constrained webview + native logout. Currently "couldn't load profile." |
| Authentication | Complete | Real Instagram login page in-app; credentials never touch native code. |

Deliberately absent: **Reels, Explore, and Suggested Posts**- features that Strand exists to remove.

## 🗺 Roadmap

Functional Fixes and Improvements
- *Fix viewership*: Stories and posts are currently marked as unviewed on the backend unless interacted with via a native like.
- *Fix commenting*: Properly bridge the native text input to the underlying Instagram web comment UI.
- *Implement profile*: Investigate and patch the routing logic causing the "couldn't load profile" error in the constrained webview.

User Experience Improvement Features
- *Optimize anti-bot performance*: Current write actions rely on random artificial delays to evade bot detection, slowing down the app. This will be replaced with more sophisticated, performant human-mimicry interactions.
- *Construct native DM interface*: Build a fully native Direct Messaging interface to replace the constrained webview bridge- an aesthetics/UX improvement.

## 📂 Architecture

```
strand/
├── strandApp.swift              App entry point
├── ContentView.swift            Root: Auth vs. Main tab switch
├── Managers/
│   ├── SessionManager.swift     Auth state via sessionid cookie
│   ├── InstagramAPIBridge.swift Hidden webview → private API reads
│   └── WebActionBridge.swift    Hidden webview → real-UI writes (like/comment)
├── Models/
│   └── Post.swift               Domain models + raw IG DTO mapping/filtering
└── Views/
    ├── MainTabView.swift              Feed / Messages / Profile tab shell
    ├── FeedView.swift                 Native feed + comments sheet
    ├── StoriesView.swift              Native story tray
    ├── StoryPlayerView.swift          Native fullscreen story player
    ├── MessagesView.swift             DMs (constrained webview)
    ├── ProfileView.swift              Profile (constrained webview)
    ├── AuthenticationView.swift       Login flow
    └── ConstrainedInstagramWebView.swift  Path-locked webview w/ JS watchdog
```

## Requirements

- Xcode with iOS 26 SDK
- Swift 5
- An Instagram account (login is interactive, in-app- no credentials or API keys are stored in the project)

## Getting started

1. Open `strand.xcodeproj` in Xcode.
2. Select a simulator or device and run.
3. Log in with your Instagram account when prompted.

## ⚠️ Disclaimer

Strand relies on Instagram's private, undocumented API and is not affiliated with, endorsed by, or supported by Instagram or Meta. Use at your own risk- Instagram's API and anti-automation measures may change at any time.

## A note on how this was built

The product problem and the constraints came from my own experience- existing "Instagram blocker" apps are web wrappers with features crudely stripped out, and they feel sluggish; I wanted something that felt genuinely native.

I'm not a web developer or iOS specialist- my primary programming proficiencies are in C++ and Python. Therefore, the technical specification and execution was done through AI-assisted development, with me directing scope, continuously testing with a real account, and diagnosing/proposing root causes (e.g. tracing a broken scroll-lock to a CSS/JS distinction- disabling scroll in CSS doesn't stop a carousel's own scroll-driving JS).