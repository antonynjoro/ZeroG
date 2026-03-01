# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## After Making Changes

After any code change to the Swift app, always run the build script and remind the user to restart the app:

```bash
cd ZeroGSwift && ./build_app.sh
```

Then tell the user: **"Build complete — please quit and relaunch ZeroG.app to test your changes."**

---

## Project Overview

ZeroG is a privacy-focused voice typing macOS app. Hold Left Control to record; release to transcribe and paste into any app. Hold Control+Q to additionally polish the text via Gemini.

The project has **two parallel implementations**:
- **`ZeroGSwift/`** — Native Swift app (active development, current branch: `swift-native`). Uses WhisperKit + AVFoundation + SwiftUI.
- **`zerog/`** — Original Python app (legacy). Uses MLX Whisper + sounddevice + pyobjc.

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

**State machine**: `ZeroG/Core/AppStateMachine.swift` — `AppStateMachine: ObservableObject` publishes `currentState: AppState` via Combine. States: `loading(String) → idle → recording → processing → success/error(String)`. All UI components subscribe to this via `$currentState`. Also publishes `audioLevel: Float` (0–1) for HUD visualization and `useGemini: Bool` for session context.

**Data flow**:
```
KeyMonitor (CGEvent tap)
  → onStartRecording / onStopRecording(useGemini) callbacks
  → AudioRecorder
      → AVAudioEngine tap → processAudioBuffer (silence detection + level metering)
      → stopRecording → transcribeAndInject (background Task)
          → TranscriptionEngine.transcribe([Float]) → WhisperKit
          → GeminiService.process(text) (optional)
          → TextInjector.injectText (clipboard snapshot → Cmd+V → restore)
  → AppStateMachine (state transitions + audioLevel updates)
  → StatusBarController + HUDPanelController (observe via Combine)
```

**Key implementation notes**:
- `KeyMonitor` uses `CGEvent.tapCreate(.listenOnly)` — interrupt-driven, <0.1% idle CPU. The event tap monitors `flagsChanged` (Left Control keycode 59) and `keyDown` (Q keycode 12 for Gemini mode).
- `AudioRecorder` captures at native sample rate (usually 44.1/48kHz), downsamples to 16kHz via stride for WhisperKit. Silence detection uses 5s RMS threshold (0.015).
- `TextInjector` snapshots the full pasteboard before injection and restores it 600ms after pasting.
- `Config` reads from `.env` file adjacent to the `.app` bundle, then falls back to `UserDefaults`, then hardcoded defaults. Gemini API key is stored in `UserDefaults` (set via menu bar dialog).
- `TranscriptionEngine` downloads the WhisperKit model (`large-v3-v20240930_turbo`) on first launch via `WhisperKit.download()`, then loads it with Neural Engine compute units.

**GUI**: Both `StatusBarController` and `HUDPanelController` are Cocoa-native (not SwiftUI views), subscribing to `AppStateMachine` via Combine `sink`.

### macOS Permissions Required
- Input Monitoring (for CGEvent tap)
- Accessibility (for Cmd+V simulation)
- Microphone (for AVAudioEngine)

Grant in System Settings → Privacy & Security. If the event tap fails to install, the app logs a detailed instructions message.

### Dependencies (`ZeroGSwift/Package.swift`)
- `WhisperKit` (≥0.9.0) — on-device speech recognition via Apple Neural Engine
- `GoogleGenerativeAI` (≥0.5.0) — optional Gemini API integration
- macOS 14+ required

---

## Python App (`zerog/`)

### Commands

```bash
# Setup
./setup.sh
source .venv/bin/activate

# Run
python main.py

# Test
python -m pytest tests/
python -m pytest tests/test_main.py  # single file
python -m pytest tests/test_state.py::TestClassName::test_method  # single test

# Build .app bundle
python setup.py py2app
```

### Architecture

- `main.py` → `zerog/app.py:ZeroGApp` (Cocoa lifecycle)
- `zerog/core/state.py` — Singleton `StateMachine` with Observer pattern; states: `IDLE → RECORDING → PROCESSING → SUCCESS/ERROR`
- `zerog/core/recorder.py` — `AudioRecorder` with MLX Whisper + sounddevice, parallel chunk transcription
- `zerog/core/input.py` — `KeyMonitor` polling `CGEventSourceKeyState` every 50ms
- `zerog/core/gemini.py` — Gemini integration using prompt from `gemini_prompt.txt`
- `zerog/core/typer.py` + `clipboard.py` — Text injection with clipboard fallback
- `zerog/gui/menu.py` — Status bar menu controller
- `zerog/gui/hud.py` — Floating HUD with audio level visualization

**Config**: `.env` file with `DEBUG=True/False` and `GOOGLE_API_KEY`. Debug log written to `mac_dictate.log`.

---

## Shared Assets

- `ZeroG/Resources/gemini_prompt.txt` — System prompt loaded by both implementations for Gemini polishing
