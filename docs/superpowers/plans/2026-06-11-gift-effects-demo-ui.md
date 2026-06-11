# Gift Effects Demo UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the iOS example app into a gift-effect demo UI driven by `gift_effects_svga.json`.

**Architecture:** Keep the player library untouched and implement the feature inside the `Examples` app. Add small, testable gift metadata types, then make `ViewController` own the programmatic UIKit layout, filtering, selection, and playback commands.

**Tech Stack:** Swift, UIKit, Swift Testing, Xcode iOS Simulator build, existing `SVGAPlayerView`.

---

### Task 1: Gift Metadata Tests

**Files:**
- Modify: `Examples/ExamplesTests/ExamplesTests.swift`

- [ ] **Step 1: Replace the placeholder test file with focused tests**

```swift
//
//  ExamplesTests.swift
//  ExamplesTests
//
//  Created by Sondra on 2026/3/23.
//

import Foundation
import Testing
@testable import Examples

struct ExamplesTests {

    @Test func decodesGiftEffectsFromJSON() throws {
        let data = """
        [
          {
            "name": "萌萌花束",
            "url": "https://qiniu-xbyy.yinyou.live/channel/gift/AMZZpp-1778586158262.svga"
          },
          {
            "name": "欢乐节拍",
            "url": "https://ymres.yinyou.live/channel/gift/Zy76Wn-1679971764876.svga"
          }
        ]
        """.data(using: .utf8)!

        let effects = try GiftEffectsDataSource.decode(data)

        #expect(effects.count == 2)
        #expect(effects[0].name == "萌萌花束")
        #expect(effects[0].sourceLabel == "qiniu")
        #expect(effects[1].sourceLabel == "ymres")
    }

    @Test func filtersGiftEffectsByNameAndSource() {
        let effects = [
            GiftEffect(name: "萌萌花束", url: URL(string: "https://qiniu-xbyy.yinyou.live/a.svga")!),
            GiftEffect(name: "欢乐节拍", url: URL(string: "https://ymres.yinyou.live/b.svga")!)
        ]

        #expect(GiftEffectsDataSource.filter(effects, query: "花束").map(\.name) == ["萌萌花束"])
        #expect(GiftEffectsDataSource.filter(effects, query: "ymres").map(\.name) == ["欢乐节拍"])
        #expect(GiftEffectsDataSource.filter(effects, query: "  ").count == 2)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail because the model does not exist**

Run: `xcodebuild test -project Examples/Examples.xcodeproj -scheme Examples -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: FAIL with compiler errors for `GiftEffectsDataSource` and `GiftEffect`.

### Task 2: Gift Metadata Implementation

**Files:**
- Create: `Examples/Examples/GiftEffect.swift`

- [ ] **Step 1: Add the gift model and data source helpers**

```swift
//
//  GiftEffect.swift
//  Examples
//
//  Created by Sondra on 2026/6/11.
//

import Foundation

struct GiftEffect: Decodable, Equatable {
    let name: String
    let url: URL

    var sourceLabel: String {
        guard let host = url.host()?.lowercased() else { return "unknown" }
        if host.contains("qiniu") { return "qiniu" }
        if host.contains("ymres") { return "ymres" }
        if host.contains("res.") { return "res" }
        return host
    }
}

enum GiftEffectsDataSource {
    static func load(from bundle: Bundle = .main) throws -> [GiftEffect] {
        guard let url = bundle.url(forResource: "gift_effects_svga", withExtension: "json") else {
            throw GiftEffectsDataSourceError.missingResource
        }

        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [GiftEffect] {
        try JSONDecoder().decode([GiftEffect].self, from: data)
    }

    static func filter(_ effects: [GiftEffect], query: String) -> [GiftEffect] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return effects }

        return effects.filter { effect in
            effect.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            effect.sourceLabel.localizedCaseInsensitiveContains(trimmedQuery) ||
            (effect.url.host()?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }
}

enum GiftEffectsDataSourceError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "gift_effects_svga.json was not found in the app bundle."
        }
    }
}
```

- [ ] **Step 2: Run the tests and verify they pass**

Run: `xcodebuild test -project Examples/Examples.xcodeproj -scheme Examples -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS for both `ExamplesTests` tests.

### Task 3: UIKit Demo Redesign

**Files:**
- Modify: `Examples/Examples/ViewController.swift`

- [ ] **Step 1: Replace the single-player controller with a programmatic gift demo screen**

Implement a `ViewController` that:
- Keeps the storyboard outlet optional and removes it from the screen when loaded.
- Builds a root vertical stack with header, preview stage, controls, search field, and collection view.
- Loads `[GiftEffect]` from `GiftEffectsDataSource.load()`.
- Selects and plays the first gift on launch.
- Filters the collection view through `UISearchTextField`.
- Uses a custom `GiftEffectCell` for gift names, source badges, and selected state.
- Handles replay, pause/resume, and loop toggle through `SVGAPlayerView`.
- Shows loading, error, and empty states in overlay labels.

- [ ] **Step 2: Run tests after the UI rewrite**

Run: `xcodebuild test -project Examples/Examples.xcodeproj -scheme Examples -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS for the metadata tests and successful app target compilation.

### Task 4: Final Verification

**Files:**
- Verify: `Examples/Examples/ViewController.swift`
- Verify: `Examples/Examples/GiftEffect.swift`
- Verify: `Examples/ExamplesTests/ExamplesTests.swift`
- Verify: `Examples/Examples/gift_effects_svga.json`

- [ ] **Step 1: Build the example app**

Run: `xcodebuild -project Examples/Examples.xcodeproj -scheme Examples -destination 'generic/platform=iOS Simulator' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Review the working tree**

Run: `git status --short`

Expected: changes are limited to the example app, tests, plan document, and the JSON resource.

