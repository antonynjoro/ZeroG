# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Documents

- [`docs/app-store-readiness-audit.md`](docs/app-store-readiness-audit.md) — Full audit of App Store compliance, production readiness, and maintainability (2026-05-03). Contains the prioritised fix checklist and the rationale for direct-download distribution over Mac App Store submission.
- [`docs/distribution-signing.md`](docs/distribution-signing.md) — How to sign (Developer ID) and notarize ZeroG for direct download. One-time cert/credential setup plus the `build_app.sh` env-var build modes.
- [`docs/spikes/fluidaudio-parakeet-spike.md`](docs/spikes/fluidaudio-parakeet-spike.md) — In-progress spike (branch `spike/fluidaudio-parakeet`): evaluating FluidAudio/Parakeet as a replacement for WhisperKit. Cross-session tracking doc with the decision rubric, findings table, and decision log.
- [`docs/macos-permissions-gotchas.md`](docs/macos-permissions-gotchas.md) — **READ BEFORE touching anything TCC/permissions-related.** Hard-won gotchas: tapCreate succeeding is NOT a permission signal, AXIsProcessTrusted caches true per-process, quit-before-tccutil-reset testing protocol, activation-policy flips kill the event tap, Console logging redaction.

## After Making Changes

After any code change to the Swift app, always run the build script and remind the user to restart the app:

```bash
cd ZeroGSwift && ./build_app.sh
```

Then tell the user: **"Build complete — please quit and relaunch ZeroG.app to test your changes."**

---

## Project Overview

ZeroG is a privacy-focused voice typing macOS app. Hold a trigger key (default Left Control) to record; release to transcribe on-device and paste into any app. A global Polish shortcut (default ⌃⌥P) cleans up the last transcription via **Apple Foundation Models** (on-device, macOS 26 + Apple Intelligence) and pastes it. Everything runs on the Mac — audio and text never leave it.

The project has one active implementation:
- **`ZeroGSwift/`** — Native Swift app. Uses WhisperKit + AVFoundation + SwiftUI.

## Swift App (`ZeroGSwift/`)

### Commands

```bash
# Build and run (development)
cd ZeroGSwift
swift run

# Build release binary
swift build -c release

# Package as .app bundle (output: ZeroGSwift/build/ZeroG.app)
cd ZeroGSwift && ./build_app.sh

# Run tests
swift test

# Run a single test
swift test --filter ZeroGTests.TestClassName/testMethodName
```

### Architecture

**Entry point**: `ZeroG/ZeroGApp.swift` — `@main ZeroGApp` struct with `AppDelegate` that wires all components together on `applicationDidFinishLaunching`.

**State machine**: `ZeroG/Core/AppStateMachine.swift` — `AppStateMachine: ObservableObject` publishes `currentState: AppState` via Combine. States: `loading(String) → idle → recording → processing → success/error(String)`, plus `polishing` (on-device polish running) and `needsPermission(String)` (paste blocked, lingering HUD). All UI components subscribe via `$currentState`. Also publishes `audioLevel: Float` (0–1) and `lastTranscription: String?`.

**Data flow**:
```
KeyMonitor (CGEvent tap)
  → onStartRecording / onStopRecording callbacks (and onPolishShortcut)
  → AudioRecorder
      → AVAudioEngine tap → processAudioBuffer (silence detection + level metering)
      → stopRecording → transcribeAndInject (background Task)
          → Transcribing.transcribe([Float]) → Parakeet (default) / WhisperKit
          → TextInjector.injectText (AX preflight → clipboard snapshot → Cmd+V → restore)
  → AppStateMachine (state transitions + audioLevel updates)
  → StatusBarController + HUDPanelController (observe via Combine)

Polish (separate, post-hoc): onPolishShortcut / menu → PolishService.polish
  (Apple Foundation Models, on-device) → .polishing HUD → paste/copy.
```

**Key implementation notes**:
- `KeyMonitor` uses `CGEvent.tapCreate(.listenOnly)` — interrupt-driven, <0.1% idle CPU. It monitors `flagsChanged` (the trigger modifier) and `keyDown` (the configurable global Polish chord, exact-match).
- `AudioRecorder` captures at native sample rate (usually 44.1/48kHz), downsamples to 16kHz for the engine. Silence detection via RMS.
- `TextInjector` preflights `AXIsProcessTrusted()` (above the pasteboard snapshot), then snapshots the pasteboard, pastes, and restores it 600ms later. Returns `false` when Accessibility is missing → caller falls back to copy + `.needsPermission`.
- `PolishService` (`ZeroG/Core/PolishService.swift`) wraps Apple Foundation Models behind `@available(macOS 26,*)`; the façade reports `isAvailable`/`unavailableReason` so the menu + onboarding disable with a reason on unsupported Macs. App floor stays macOS 14.
- `Config` reads from `.env` (skipped under protected folders), then `UserDefaults`, then defaults. No cloud keys — cloud Gemini was removed.
- `TranscriptionEngine` downloads the WhisperKit model (`large-v3-v20240930_turbo`) on first launch via `WhisperKit.download()`, then loads it with Neural Engine compute units.

**GUI**: Both `StatusBarController` and `HUDPanelController` are Cocoa-native (not SwiftUI views), subscribing to `AppStateMachine` via Combine `sink`.

### macOS Permissions Required
- Microphone (for AVAudioEngine)
- Accessibility (for both the listen-only CGEvent key tap AND Cmd+V paste)

Only **two** permissions. Input Monitoring is NOT required: ZeroG's key listener is a listen-only `CGEvent` tap, which an Accessibility-trusted process is already allowed to create — so Accessibility covers both trigger-key detection and paste injection. The guided onboarding wizard (`GUI/OnboardingWindow.swift`) requests exactly these two.

Grant in System Settings → Privacy & Security. If the event tap fails to install, the app logs a detailed instructions message.

### Dependencies (`ZeroGSwift/Package.swift`)
- `WhisperKit` (≥0.9.0) — on-device speech recognition via Apple Neural Engine
- `FoundationModels` (system framework, macOS 26+) — on-device LLM for the optional Polish step (weak-linked; gated)
- macOS 14+ required

---

## Shared Assets

- `ZeroGSwift/ZeroG/Resources/polish_prompt.txt` — System prompt for the on-device Polish step
