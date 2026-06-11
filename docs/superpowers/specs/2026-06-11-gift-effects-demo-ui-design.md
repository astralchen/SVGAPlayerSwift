# Gift Effects Demo UI Design

## Context

The current example app contains a single storyboard-hosted `SVGAPlayerView` and plays the bundled `banner.svga` when the view appears. `Examples/Examples/gift_effects_svga.json` adds a larger remote test set: 105 named gift effects across `ymres.yinyou.live`, `qiniu-xbyy.yinyou.live`, and `res.yinyou.live`.

The redesigned example should use that JSON file as the primary data source and turn the app into a practical gift-effect demo surface for browsing, selecting, and controlling SVGA playback.

## Goals

- Load gift effect metadata from `gift_effects_svga.json` in the app bundle.
- Show a polished UIKit example UI that demonstrates real remote SVGA playback.
- Combine three demo needs in one screen: gift browsing, live-gift style selection, and player controls.
- Keep changes scoped to the example app. Do not change `SVGAPlayer` core behavior unless a build issue exposes a required integration fix.

## Non-Goals

- No persistence, download management UI, or custom cache controls.
- No authentication, payment, or real gift sending behavior.
- No generated thumbnails for remote SVGA files. Gift cards use text and source badges.
- No major storyboard redesign. The controller can continue to be launched from storyboard while its content is built programmatically.

## UI Design

The screen is a single UIKit view controller with three vertical areas:

1. Header
   - App title: gift effect demo.
   - Current gift name.
   - Count summary based on decoded JSON.

2. Preview stage
   - A large `SVGAPlayerView` using `.scaleAspectFit`.
   - Dark, quiet stage styling so colorful gift effects have contrast.
   - Overlay labels for loading, failed, and empty states.
   - The selected effect starts playing automatically.

3. Gift browser and controls
   - Search field filtering gifts by name or source host.
   - A compact collection view grid for all gifts.
   - Selected card state.
   - Each card displays gift name and a host badge such as `ymres` or `qiniu`.
   - Control row includes replay, pause/resume, and loop toggle.

## Data Flow

- Add a `GiftEffect` model in the example app:
  - `name: String`
  - `url: URL`
  - derived `sourceLabel`
- `ViewController` decodes `[GiftEffect]` from `gift_effects_svga.json` in `Bundle.main`.
- The full decoded list is retained separately from the filtered list.
- Selecting a gift updates the selected item, UI labels, and calls `SVGAPlayerView.play(url:)`.
- Search updates the filtered collection view while preserving selection when possible.

## Playback Behavior

- On first load, select and play the first decoded gift effect.
- Before starting a new effect, show a loading state and clear stale errors.
- Use `SVGAPlayerView.onLoadFailed` to show a concise error state.
- Use `SVGAPlayerView.onFinished` only for finite-loop playback state updates.
- The loop toggle maps to `playerView.loops`: `0` for infinite loop, `1` for one-shot playback.
- Replay calls `play(url:)` again for the selected gift.
- Pause/resume calls `pauseAnimation()` and `startAnimation()`.

## Component Boundaries

- `GiftEffect`: decodable value type plus small URL/source helpers.
- `GiftEffectCell`: collection view cell responsible only for displaying a gift card.
- `ViewController`: owns layout, search/filter state, selection, and playback commands.

The example remains intentionally small, so introducing a separate view model is unnecessary unless the controller grows beyond simple UI coordination.

## Error Handling

- If the JSON file is missing or cannot decode, show an empty/error state in the preview and keep controls disabled.
- If a remote SVGA fails to load, keep the selected gift visible and show a retry-friendly error label.
- If search returns no results, show an empty collection message or background label.

## Testing And Verification

- Build the `Examples` app target for an iOS Simulator destination.
- Confirm `gift_effects_svga.json` is available in the app bundle through the file-synchronized Xcode project group.
- Confirm the app compiles with the new UIKit code.
- Manual simulator verification should cover:
  - First gift auto-selection.
  - Selecting another gift.
  - Searching by Chinese gift name.
  - Searching by source label.
  - Replay, pause/resume, and loop toggle.
  - Remote load failure state if network access is unavailable.

