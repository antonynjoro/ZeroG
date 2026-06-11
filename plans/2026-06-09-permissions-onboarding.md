---
status: complete
created: 2026-06-09
completed: 2026-06-10
branch: feature/permissions-onboarding (off dev)
mockup: mockups/onboarding-flow-mockup.html (gitignored, Variant A — design source of truth)
stack: native SwiftUI in NSWindow via NSHostingView (matches HUDPanel)
icons: gradient PNG assets (HUDIcons pipeline)
fidelity: match the mockup; native window chrome only
---

# Guided Permissions Onboarding — Wizard Flow

## Context

ZeroG needs three macOS permissions (Microphone, Input Monitoring, Accessibility) to function at all, but today there is no onboarding: the app launches straight to idle, permission failures are logged to the console only (Input Monitoring tap failure: `KeyMonitor.swift:95-111`), and a denied Accessibility permission makes paste fail *silently while the HUD still shows success* (`TextInjector.swift:89-118`, unconditional `.success` at `AudioRecorder.swift:282`). A user who misses one permission gets a dead app with no guidance.

We explored four onboarding patterns in an interactive HTML mockup (research baseline: Wispr Flow, superwhisper, Rectangle, Loom, Apple HIG just-in-time guidance). **Decision: Variant A — a wizard with one permission per screen**, Wispr Flow style: welcome screen → one full-screen step per permission with explanation and live grant detection → "try it now" finish screen.

### Product decisions (confirmed with Antony)

1. **Window is closable, but the app is unusable without permissions.** While any permission is missing, pressing the hotkey re-opens the setup wizard instead of recording. Honest limitation: if *Input Monitoring* itself is missing, the hotkey press is undetectable (the event tap is dead) — coverage there is the wizard auto-showing on every launch plus a menu-bar status line ("Hotkey disabled — open Setup").
2. **Re-show on every launch** while anything is missing. No `hasCompletedOnboarding` flag — gating derives from live permission status, so it self-heals if the user revokes a permission later.
3. **Accessibility missing at paste time:** no fake success. Text is auto-copied to the clipboard; the HUD **lingers (no auto-reset)** showing **"Copied — press ⌘V to paste. Click to fix permissions."** A single click anywhere on the HUD opens the wizard at the Accessibility step. **Message-only, no in-HUD button** (decided 2026-06-10): the floating panel is click-proof by default and a real button is fiddly AppKit; the message + click-to-open gives the same outcome with far less plumbing. Same `lastTranscription` is stored, so menu "Copy Last Transcription" also works.
4. **Custom stage icons** matching the existing ZeroG icon language (see Icon plan below) — no emoji, no bare SF Symbols.

## Branching (do first)

1. Merge `spike/fluidaudio-parakeet` into `dev` (plain merge — the spike **branch is kept**, not deleted, until the Parakeet soak is validated). Push dev.
2. Create `feature/permissions-onboarding` off `dev`. All work below lands there.

## Rendering architecture (decided 2026-06-09)

**Native SwiftUI**, hosted in a standard `NSWindow` via `NSHostingView` — same pattern as the existing HUD (`HUDPanel.swift:223`), which itself "Replaces the Python WebKit/HTML/Tailwind HUD with native SwiftUI — no WebKit process needed." A WKWebView was rejected: it would reintroduce the WebKit process the team deliberately removed and require JS↔Swift bridges for every permission button. macOS 14 (min target) supports every API below.

**Fidelity target: ~98–100% one-for-one** with the mockup. The HTML mockup (`mockups/onboarding-flow-mockup.html`) is the visual source of truth; port effect-for-effect. Mockup→SwiftUI mapping (all confirmed feasible on macOS 14):

| Mockup effect | SwiftUI implementation |
|---|---|
| Dark gradient window bg | `ZStack { LinearGradient }` |
| Segmented progress (plain gray → gradient slice on complete, one continuous sweep, active glow) | `HStack` of capsules; one `LinearGradient` `.mask`ed by the filled capsules; `.shadow` on active |
| Icon halo (radial bg + rotating accent arc + breathe) | `RadialGradient` + `Circle().stroke(AngularGradient)` with animated `.rotationEffect` + animated `.shadow` |
| Grant celebration (green sweep, ripple, ✓ badge spring) | color swap + `Circle` scale/opacity + badge `.scaleEffect` `.spring` |
| Done waveform (varied bar heights + speeds) | `HStack` of `RoundedRectangle`, per-bar `.scaleEffect(y:)` with `Animation.easeInOut(duration:).repeatForever(autoreverses:true).delay()` |
| Typewriter + blinking caret | `Timer`/`TimelineView` prefix + caret opacity `.repeatForever` |
| Trigger pills (hover lift, select-glyph pop) | `LazyVGrid` of buttons, `.onHover` → offset, select → border + `.scaleEffect` pop |
| App-icon float | `Image` + animated `.offset(y:)` `.repeatForever` |
| Staggered entrance (riseIn) | per-child `.opacity`/`.offset` with delayed `.animation` on appear |
| Exact easing `cubic-bezier(.2,.8,.2,1)` | `.timingCurve(0.2, 0.8, 0.2, 1)` |
| `prefers-reduced-motion` | `@Environment(\.accessibilityReduceMotion)` gates every `repeatForever` |

**Stage icons = gradient PNG assets.** Export the three onboarding SVGs (`onboard-mic/keys/paste`) to @1x/@2x/@3x PNGs via the existing `rsvg-convert` HUDIcons pipeline, into the asset catalog. App icon (welcome) and success icon (done) reuse existing assets. No SVG runtime rendering, no hand-ported paths.

**Where mockup vs macOS idiom conflict → mockup wins.** Solid dark gradient panel, custom teal buttons, our orbit-gradient palette as designed. Native chrome limited to the standard titled window (traffic lights). No system vibrancy, no system accent override.

## Wizard UI spec (Variant A — final, matches mockup)

Single reused `NSWindow` (`.titled, .closable`, ~470×590, centered, `NSHostingView` + SwiftUI, dark styling reusing `HUDColors`). App is `LSUIElement`, so `show()` must `NSApp.activate(ignoringOtherApps: true)` before `makeKeyAndOrderFront` (same pattern as the Gemini key dialog, `StatusBarController.swift:214-216`).

Window body = fixed-height flex column equivalent: **segmented progress row** (inset from top) · **content** (vertically centered) · **footer** (pinned button). Each step: an **eyebrow** (uppercase teal, e.g. "Permission 2 of 3"), an **icon halo** (or app icon on welcome), title, sub, optional controls; primary button in the footer. Step changes swap only the content (window shell persists) so the staggered entrance replays and the progress animates smoothly.

Steps (state machine inside the view model):

Copy is final per the mockup: em-dash-free, and the welcome screen is **key-agnostic** (it must not name a specific key, since the key is chosen later).

| # | Step | Eyebrow | Content (final copy) | Advance condition |
|---|------|---------|----------------------|-------------------|
| 0 | Welcome | "Welcome" | App icon (floating), **"Voice typing, anywhere"**, "Hold a key, speak, and release. Your words land wherever your cursor is.", privacy line ("Runs entirely on your Mac. Your audio never leaves it."), **Get started** + footnote "Three quick permissions. About a minute." | button |
| 1 | Microphone | "Permission 1 of 3" | Halo + mic icon, "So ZeroG can hear your voice while you hold the key.", **Allow Microphone** → `AVCaptureDevice.requestAccess` (native dialog) | status flips granted → auto-advance |
| 2 | Input Monitoring | "Permission 2 of 3" | Halo + keys icon, "So ZeroG knows the moment you press and release your trigger key.", **Open System Settings** (deep link), footnote "Turn on the ZeroG toggle, then come back. We'll detect it for you." | polling detects grant → retry `keyMonitor.start()` → auto-advance; if tap re-creation fails, show "Quit and reopen ZeroG" note |
| 3 | Accessibility | "Permission 3 of 3" | Halo + paste icon, "So ZeroG can type the transcribed text into any app.", **Open System Settings** (deep link) | polling detects grant → auto-advance |
| 4 | Trigger key | "Almost done" | **"Pick your trigger key"**, "Hold it to record, release to transcribe. Pick one you won't press by accident.", 2×3 grid of the 6 keys (`TriggerKey.swift`: Left Control [default], Right Control, Left/Right Option, Right Shift, Fn/Globe), selected pill highlighted; **Use [key]** persists via `Config.setTriggerKey` | button |
| 5 | Done | "You're ready" | Green halo + success icon, **"All set"**, "Try it now. Hold [glyph + key] and speak.", **teaching demo** (resting waveform + typewriter that types "testing, one two three" with blinking caret), **Start using ZeroG** | button closes window |

Trigger-key step reuses the existing `TriggerKey.all` list and `Config.setTriggerKey` (already wired to the menu picker + `KeyMonitor` change notification) — picking here is identical to the menu "Record Key" submenu, just surfaced during onboarding. Placed *after* permissions so the Done step can prompt "hold [your key]" and so the key is testable immediately (Input Monitoring already granted by then).

Mechanics:
- **Segmented progress** row (one per step): incomplete = plain gray; complete = its slice of the continuous orbit gradient (`#19D7DE → #8C5CFF → #FFB23F`) reconstructed across all segments; the current segment carries a soft glow. Inset from the top edge (not flush chrome).
- **Re-entry behavior:** when the wizard opens and some permissions are already granted, skip Welcome and granted steps — jump straight to the first missing permission. (Wizard's weakness for re-entry, patched.)
- **Polling:** 1s `Timer` while the window is open only (no TCC change notification exists). `CGRequestListenEventAccess()` returns `false` immediately when not yet granted — grant detection is *only* via polling, never the request's return value.
- Each non-native step also fires the prompting request once (`CGRequestListenEventAccess`, `AXIsProcessTrustedWithOptions(prompt: true)`) so the app appears pre-listed in the Settings pane.

## API choices

| Permission | Check (no prompt) | Request |
|---|---|---|
| Microphone | `AVCaptureDevice.authorizationStatus(for: .audio)` | `AVCaptureDevice.requestAccess(for: .audio)` |
| Input Monitoring | `CGPreflightListenEventAccess()` | `CGRequestListenEventAccess()` |
| Accessibility | `AXIsProcessTrusted()` | `AXIsProcessTrustedWithOptions(prompt: true)` |

CG pair chosen over IOHID equivalents: same TCC service (`kTCCServiceListenEvent`), but documented specifically for event taps (exactly what `KeyMonitor` creates) and CoreGraphics is already imported.

Deep links via `NSWorkspace.shared.open`:
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`
- `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`

Known field issue: macOS Tahoe (26) changed Settings pane IDs and broke these links in Wispr Flow until patched — centralize the URLs in one place (`PermissionKind.settingsURL`) so a future fix is one line per pane.

## Icon plan

Existing language (`ZeroGSwift/ZeroG/Resources/HUDIcons/*.svg`): 64×64 viewBox, stroke-based (4–5px, round caps/joins), signature "orbit" gradient strokes `#19D7DE → #8C5CFF → #FFB23F`, cream fills `#FFF9EA`/`#F6F0E3`, neutral gray supports `#5F6470`. Loaded as 128×128 PNGs (2× export) via `bundle.url(forResource:withExtension:"png", subdirectory:"HUDIcons")` (`HUDPanel.swift:155`).

New assets — same folder, same dual SVG+PNG convention, same style:

| Asset | Step | Motif sketch |
|---|---|---|
| `onboard-mic.svg/png` | Microphone | mic capsule (cream fill) wrapped by orbit-gradient sound wave — close cousin of `hud-recording` but calmer (setup, not live recording) |
| `onboard-keys.svg/png` | Input Monitoring | keycap with `⌃` glyph (cream fill, gray base) with orbit-gradient arc passing through it |
| `onboard-paste.svg/png` | Accessibility | text-insertion caret / cursor with flowing orbit-gradient line landing into a text line |
| Welcome | reuse `AppIcon` (already in `Assets.xcassets`) | — |
| Done | reuse `hud-success` | — |

Process:
1. Hand-author the three SVGs in the existing style (copy gradient defs from `hud-recording.svg`).
2. Export PNGs at 128×128: `rsvg-convert -w 128 -h 128 onboard-mic.svg > onboard-mic.png` (rsvg-convert confirmed installed at `/opt/homebrew/bin/rsvg-convert`).
3. Preview all three inside the HTML mockup (swap emoji for the SVGs) for Antony's sign-off **before** wiring into Swift.

## Implementation

### New files

1. **`ZeroG/Core/PermissionsManager.swift`**
   - `enum PermissionKind: CaseIterable` (microphone, inputMonitoring, accessibility) with `displayName`, `explanation`, `settingsURL`, `iconName`.
   - `enum PermissionStatus` (granted / denied / notDetermined — only mic yields the full triple; CG/AX `false` maps to `.denied`).
   - `protocol PermissionChecking` (status/request) — test seam. `SystemPermissionChecker` is the *only* type touching AVCaptureDevice/CG/AX.
   - `final class PermissionsManager: ObservableObject`: `@Published statuses`, `allGranted`, `missing`, pure `static shouldShowOnboarding(statuses:)`, `refresh()` (publishes diffs, fires `onPermissionGranted(kind)` per flip), `startPolling()/stopPolling()`, `openSettings(for:)`.

2. **`ZeroG/GUI/OnboardingWindow.swift`** — `OnboardingWindowController` (window lifecycle, single instance, polling start/stop on open/close) + `OnboardingWizardView` (SwiftUI step machine per spec above) + small `OnboardingViewModel` holding `step`, derived from `PermissionsManager` state (re-entry skip logic lives here, pure + testable).

3. **`ZeroG/Resources/HUDIcons/onboard-{mic,keys,paste}.{svg,png}`** — per icon plan.

4. **`ZeroGTests/PermissionsManagerTests.swift`** — `FakePermissionChecker`; aggregation (`allGranted`/`missing`), gating (`shouldShowOnboarding` incl. mic `.notDetermined`), refresh diffing (grant flip fires callback exactly once, right kind, nothing when unchanged).

5. **`ZeroGTests/OnboardingViewModelTests.swift`** — re-entry step selection (all missing → welcome; mic granted → jump to inputMonitoring; all granted → done), auto-advance on grant.

### Modified files

6. **`ZeroG/Core/KeyMonitor.swift`** — `start()` → `@discardableResult -> Bool`, add `private(set) var isRunning`, guard double-start (currently a second `start()` would leak a tap and double-register the observer), `return false` in the existing failure branch (keep the log as fallback).

7. **`ZeroG/ZeroGApp.swift`** — add `permissionsManager` + `onboardingController`. Replace unconditional `keyMonitor.start()` (line 78): refresh statuses; start tap only if Input Monitoring granted; if anything missing → show wizard (model download continues concurrently — do **not** delay `transcriptionEngine.initialize()`). Wire `onPermissionGranted`: inputMonitoring grant → retry `keyMonitor.start()`; on retry failure set relaunch-required flag the wizard step renders. Gate `onStartRecording`: any permission missing → show wizard instead of recording. Observe `Notification.Name("ZeroG.permissionsNeeded")` → show wizard.

8. **`ZeroG/Core/TextInjector.swift`** — `injectText` → `@discardableResult -> Bool`; `guard AXIsProcessTrusted() else { return false }` *before* touching the pasteboard (never clobber the clipboard when paste can't happen).

9. **`ZeroG/Core/AudioRecorder.swift`** (lines 279-284) — `let injected = TextInjector.injectText(finalText)`; if false: copy text to clipboard, transition to `.needsPermission`, post `ZeroG.permissionsNeeded`. (`lastTranscription` is already stored, so menu "Copy Last Transcription" also still works.)

10. **`ZeroG/Core/AppStateMachine.swift` + `Core/StatePresentation.swift`** — new state `.needsPermission(String)`: lingering, no auto-reset, persists until next user action. Update `presentation` switch + `Equatable`/`isReady` + existing tests.

11. **`ZeroG/GUI/HUDPanel.swift`** — for `.needsPermission` only: keep panel visible (no slide-out), show the message "Copied — press ⌘V to paste. Click to fix permissions." Make the panel click-through-to-action: set `ignoresMouseEvents = false` for this state and install a single click recognizer on the whole HUD that posts `ZeroG.permissionsNeeded` (→ opens wizard). **No SwiftUI buttons, no `canBecomeKey` work** — a whole-panel click is enough and sidesteps the click-proof-panel gotcha.

12. **`ZeroG/GUI/StatusBarController.swift`** — new init callback `onShowPermissions` (same pattern as `onRunBackendComparison`) + "Setup / Permissions…" menu item; status line "Hotkey disabled — open Setup" when Input Monitoring missing.

13. **`Info.plist`** — add `NSAccessibilityUsageDescription` (Mic + Input Monitoring strings already present).

## Implementation gotchas (READ BEFORE CODING — verified against the code)

These are the places the existing code behaves in a way that will silently break a naive implementation. Each is anchored to a real file:line.

**Permission APIs — check vs request are different calls; never poll with the prompting variant**
- Poll (no prompt, every 1s): `AVCaptureDevice.authorizationStatus(for:.audio)`, `CGPreflightListenEventAccess()`, `AXIsProcessTrusted()`.
- Request (prompts, ONCE on the user's button tap only): `AVCaptureDevice.requestAccess`, `CGRequestListenEventAccess()`, `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt:true])`.
- Calling the prompting variant on every poll tick spawns a system dialog every second. This is the #1 trap.
- **Microphone needs a branch the mockup does not show:** `requestAccess` only presents a dialog when status is `.notDetermined`. If status is `.denied`, `requestAccess` returns `false` with NO dialog → user is stuck. So the Mic step: `.notDetermined` → `requestAccess`; `.denied` → open System Settings deep link (same as the other two). Do not treat mic as a uniform "Allow" button.
- No existing code uses any of these APIs (grep confirmed) — all new. Needs `import AVFoundation` (mic), `import CoreGraphics` (listen-event), `import ApplicationServices` (AX).

**Threading — `@Published` state is main-thread only**
- `AVCaptureDevice.requestAccess` completion fires on an arbitrary thread; `AudioRecorder` transcription runs in a background `Task`. Every `AppStateMachine` transition and every `PermissionsManager.@Published` mutation off the main thread must hop via `DispatchQueue.main.async` / `@MainActor`. Mutating published state off-main = runtime purple warnings + glitchy UI.

**Polling Timer — retain cycle + zombie polling**
- `Timer.scheduledTimer(target: self,…)` retains the target. The `OnboardingWindowController` MUST `invalidate()` the timer in `windowWillClose` (and use weak capture), or it polls forever after the window closes — battery drain + mutating a dead view. Start polling in `show()`, stop in `windowWillClose`.

**NSWindow under `.accessory` — two AppKit footguns**
- `isReleasedWhenClosed` defaults to **true** for code-created windows. Reopening a released window crashes. Set `isReleasedWhenClosed = false` and keep the single controller instance alive; `show()` reuses the same window (never `new` a second one).
- Must `NSApp.activate(ignoringOtherApps: true)` BEFORE `makeKeyAndOrderFront` (LSUIElement app has no normal activation). Set the window content size explicitly (or give the SwiftUI root a fixed `.frame`) or the window sizes to zero/jumps.

**Adding `.needsPermission(String)` — every exhaustive switch must be updated** (`AppState` def: `AppStateMachine.swift:7-13`)
- `AppStateMachine.swift:16-20` `isReady` → return **false**.
- `AppStateMachine.swift:24-32` `statusText` → add copy.
- `StatePresentation.swift:56-123` `presentation(useGemini:)` → new descriptor: **visible, lingering**.
- `HUDPanel.swift:73-77` `iconScale`, `:81-87` `shadowIntensity`, `:45-55` content observer — these have `default:` branches so they will NOT fail to compile but may render wrong; set explicitly.
- `HUDPanel.swift:243-249` visibility: only `.idle`/`.loading` slide out, everything else slides in — so `.needsPermission` slides in by default (good), but it must NOT be auto-reset away (see next).
- Switches WITHOUT `default:` give a compile error if you miss them (free safety net); the ones with `default:` are the dangerous ones.

**`.needsPermission` must NOT auto-reset** (`AudioRecorder.swift:282-290`)
- `.success` schedules `resetToIdle()` (2s, `Config.Timing.successReset`); `.error` schedules `resetToIdle(after: errorReset)` (3s). If you copy that pattern for `.needsPermission` the HUD vanishes. It must linger until the user acts — schedule **no** reset.

**Pasteboard restore will wipe a fallback copy — the AX guard placement matters** (`TextInjector.swift:28-41`)
- `injectText` snapshots the pasteboard (`:28`), clears+writes (`:31-32`), pastes (`:35`), then after 0.6s (`Config.Timing.clipboardRestore`) **restores the original** (`:39-41`).
- The new `guard AXIsProcessTrusted() else { return false }` must be at the **very top, before the snapshot** (`:28`). Then the denied path never snapshots/clears/schedules-restore, so the fallback copy that `AudioRecorder` puts on the clipboard survives. If the guard is placed after the snapshot, the 0.6s restore timer wipes the user's transcript. (This is also why the fallback copy belongs in `AudioRecorder`, after `injectText` returns false — not inside `TextInjector`.)

**HUD panel cannot currently receive clicks** (`HUDPanel.swift:206,211,215`)
- Panel is `.borderless, .nonactivatingPanel`, `level = .screenSaver`, `ignoresMouseEvents = true`, no `canBecomeKey` override → a SwiftUI `Button` placed in it will not reliably receive clicks or highlight.
- For the `.needsPermission` Copy/Grant buttons to work: set `ignoresMouseEvents = false` (at least for that state), subclass the panel to override `canBecomeKey = true`, and `makeKeyAndOrderFront` when entering `.needsPermission`. 
- **Simpler alternative to consider** (avoids all of the above): the fallback already copies the transcript to the clipboard, so the lingering HUD can just READ "Copied — press ⌘V to paste. Click to fix permissions." and a single click anywhere opens the wizard. Decide button-in-HUD vs message-only before building this commit; the message-only path is far less AppKit-fiddly.

**KeyMonitor double-start leaks** (`KeyMonitor.swift:69-95` tap, `:122-127` observer)
- `start()` has no guard. The input-monitoring retry calls it a second time → second CGEvent tap created AND a second `triggerKeyDidChange` observer registered (double-fires). The `isRunning` guard is mandatory, not optional polish. `stop()` (`:134-150`) already tears down cleanly.

**Bundle resources — there is NO asset catalog** (`Package.swift:33-35` = `.process("Resources")`)
- Icons are loose files loaded by URL: `bundle.url(forResource:name, withExtension:"png", subdirectory:"HUDIcons")` (`HUDPanel.swift:155`), wrapped as `NSImage` → `Image(nsImage:)`. **`Image("onboard-mic")` (asset-catalog style) will silently render nothing** — there is no `.xcassets`. Load the onboarding PNGs the same URL way.
- No `@2x`/`@3x` auto-resolution from a loose-file URL. Export each onboarding PNG at ~3× its displayed point size (e.g. shown at 60pt → export 180px) and let it downscale, matching how `HUDIcons` already ship single PNGs.
- Commit the generated PNGs. `rsvg-convert` is only needed to regenerate them, not to build — do not add a build step that depends on it.

**Notification name = shared constant, not a raw string** (`Config.swift:159-161`)
- Convention: `extension Notification.Name { static let permissionsNeeded = Notification.Name("ZeroG.permissionsNeeded") }`. Use the constant in both the poster (`AudioRecorder`) and observer (`ZeroGApp`). Two raw string literals invite a typo that fails silently.

**StatusBarController callback wiring** (`StatusBarController.swift:28` init, `:24` stored, `:201-202` @objc handler; wired `ZeroGApp.swift:71-74`)
- Follow the `onRunBackendComparison` pattern exactly: add `onShowPermissions: @escaping () -> Void = {}` to init, store it, call from an `@objc` menu handler, wire at launch with `{ [weak self] in … }`.

**Testing — only the bundled app gets real TCC** (bundle id `com.zerog.app`, `Info.plist:12`)
- `swift run` attributes permissions to **Terminal**, not ZeroG → every permission appears broken and you will chase ghosts. Always test via `./build_app.sh` then `open build/ZeroG.app`. `tccutil reset … com.zerog.app` to simulate a fresh install.

**Deep-link pane IDs can drift (macOS 26 Tahoe)** — centralize the three `x-apple.systempreferences:` URLs in `PermissionKind.settingsURL` so a future pane-ID fix is one line each (this broke in Wispr Flow until patched).

## Commits (one verified unit each)

1. Branch ops: merge spike → dev (keep spike branch), create `feature/permissions-onboarding`.
2. `feat(icons): onboarding stage icons in HUD icon style` — SVGs + PNGs, previewed in mockup, user-approved.
3. `feat(core): PermissionsManager with injectable checker` — verify `swift test`.
4. `refactor(keymonitor): start() reports success, idempotent` — verify tests + manual hotkey.
5. `feat(gui): onboarding wizard window + menu item` — no launch gating yet; verify: build, open via menu, steps advance, deep links land on the right panes, icons render.
6. `feat(app): launch gating, hotkey gating, input-monitoring retry` — + Info.plist; verify with tccutil matrix below.
7. `feat(state): needsPermission lingering HUD state with Copy button`.
8. `fix(inject): accessibility preflight, copy fallback instead of fake success`.

## Verification

Manual — must use the bundled app (`swift run` attributes TCC to Terminal, not `com.zerog.app`):

```bash
cd ZeroGSwift && ./build_app.sh
tccutil reset Microphone com.zerog.app
tccutil reset ListenEvent com.zerog.app
tccutil reset Accessibility com.zerog.app
open build/ZeroG.app
```

- Fresh launch → wizard appears at Welcome; walk all steps; each grant auto-advances; hotkey comes alive after Input Monitoring grant without relaunch (or relaunch note appears).
- All granted → relaunch → wizard never appears.
- Partial matrix: revoke only Accessibility → dictate → lingering HUD with Copy button, clipboard has text, wizard opens at Accessibility step. Revoke only ListenEvent → status line shows "Hotkey disabled", wizard opens at Input Monitoring step on launch.
- Known macOS behavior: revoking Microphone while the app runs gets the process killed by TCC — expected, not a crash.

Automated: `swift test` — new PermissionsManagerTests + OnboardingViewModelTests; updated AppStateMachine/StatePresentation tests; all existing tests stay green.

After each app-affecting commit: `cd ZeroGSwift && ./build_app.sh`, then quit + relaunch ZeroG.app to test.

## Out of scope (explicitly)

- Whisper removal (still blocked on Parakeet soak — separate plan).
- Mic-test / waveform step in the Done screen (nice-to-have, add later if wanted).
- Gemini API key onboarding (optional feature; stays in the menu).

---

## As-built addendum (2026-06-10) — deviations from the plan above

Shipped on `feature/permissions-onboarding`, field-tested with Antony. Where this
section contradicts the body above, **the addendum is what shipped**.

1. **Input Monitoring removed entirely — the wizard is 5 steps / 2 permissions**
   (Welcome → Mic → Accessibility → Trigger key → Done). An Accessibility-trusted
   process may create listen-only CGEvent taps, so Accessibility covers both the
   trigger key and the paste. Proven live: hotkey works with ZeroG absent from the
   Input Monitoring pane. All CGPreflight/CGRequestListenEventAccess code deleted.
2. **`CGEvent.tapCreate` success is NOT a permission signal** — macOS can create
   the tap and silently withhold events pending trust. Two intermediate builds
   advanced the wizard prematurely on that false axiom. Grant detection is
   exclusively `AXIsProcessTrusted()` / `AVCaptureDevice.authorizationStatus` on
   the 1s poll. Full gotcha list: `docs/macos-permissions-gotchas.md`.
3. **`isReady` returns TRUE for `.needsPermission`** (plan said false): with
   false, the lingering HUD would swallow every hotkey press (KeyMonitor guards
   isReady before the permission gate runs) — soft-locking dictation. The next
   press starts a fresh recording and clears the notice; the app-level gate still
   intercepts if grants are missing (and resets the stuck `.recording` state).
4. **Done step is a live try-field, not a typewriter demo** — real focusable
   TextField, auto-focused, with a success beat (green tint + spring check +
   single ripple + trackpad haptic) the first time text lands. Doubles as the
   end-to-end mic + paste verification.
5. **Re-entry grants jump straight to Done**: after re-granting a revoked
   permission, the wizard skips the remaining steps and lands on the try-field so
   the user immediately proves the fix (fresh onboarding still passes through
   trigger-key selection).
6. **Wizard runs as a `.regular` app (Dock icon) while open**, reverting to
   `.accessory` on close — and the app rebuilds the key tap on close because the
   activation-policy flip kills it.
7. **Extra fixes shipped alongside**: deep-link button pre-lists ZeroG via the AX
   prompt before opening Settings; wizard re-fronts itself after each grant;
   `.env` probe skipped under protected folders (no Documents-access prompt);
   `Log.error` routes through `NSLog("%{public}@", …)` so it's visible in Console.

Verification: full tccutil matrix exercised manually (fresh flow, accessibility
wait-for-toggle, mic revoke re-entry, accessibility revoke at hotkey, hotkey
survives wizard close), 91 tests green.
