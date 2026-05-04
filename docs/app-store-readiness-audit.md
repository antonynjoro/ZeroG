# ZeroG — App Store & Production Readiness Audit

**Date:** 2026-05-03  
**Branch audited:** `swift-native`  
**Audited by:** Claude Sonnet 4.6 (automated multi-agent review)  
**Distribution target at time of audit:** Direct download (Developer ID), not Mac App Store

---

## The Headline Finding

**The app cannot be submitted to the Mac App Store in its current architecture.** The core mechanism — monitoring the Control key globally via `CGEvent.tapCreate` and injecting text via `CGEvent.post` — requires the sandbox to be disabled. The Mac App Store mandates sandboxing for virtually all apps. This is a structural issue, not a paperwork one. Similar productivity apps (Alfred, Raycast, TextExpander, Keyboard Maestro) resolve this by distributing **outside the App Store** as notarized Developer ID apps.

**Recommended distribution path: direct download, signed with a Developer ID certificate and notarized.**

The rest of this document is organized around that target. A separate section covers what would need to change if App Store submission is ever pursued.

---

## Submission Verdict

| Distribution path | Status |
|---|---|
| **Direct download (Developer ID + notarization)** | **Ready with fixes** |
| Mac App Store | Not ready — structural redesign required |

---

## Must-Fix Before Public Release (Direct Distribution)

- [ ] Add `NSInputMonitoringUsageDescription` to `Info.plist` — required by macOS 13.6+
- [ ] Add code signing and notarization to `build_app.sh`
- [ ] Fix `ptr.baseAddress!` force-unwraps in `AudioRecorder.swift:145,189`
- [ ] Migrate Gemini API key from UserDefaults to Keychain
- [ ] Surface permission-denied errors at launch (Input Monitoring, Microphone)
- [ ] Add model download timeout and retry with user-visible "Retry" option

## Recommended Follow-up (Post-launch)

- [ ] Clipboard restore race condition fix (changeCount check before restoring)
- [ ] Processing state timeout (60 s) to prevent stuck UI
- [ ] Max recording duration cap (5 min hard stop in AudioRecorder)
- [ ] First-launch onboarding window (permissions, hotkey, Gemini setup)
- [ ] Pin WhisperKit and GoogleGenerativeAI to exact resolved versions in `Package.swift`
- [ ] Remove debug log that prefixes Gemini output (`GeminiService.swift:105`)
- [ ] Verify `PrivacyInfo.xcprivacy` presence in built `.app` bundle
- [ ] Tests for `TextInjector`, `AudioRecorder` (especially `trimTrailingSilence`), and `KeyMonitor`
- [ ] Promote Gemini model name from hardcoded `"gemini-2.0-flash-exp"` to `Config.swift`; switch to a stable model name

---

## Detailed Findings

### Blockers — Must Fix Before Any Public Distribution

#### B1 · No code signing or notarization
**Severity:** Blocker | **Category:** Distribution  
**Evidence:** `build_app.sh` — no `codesign` or `notarytool` call.

Without a Developer ID signature and notarization, macOS Gatekeeper quarantines the app on first launch. Users see "ZeroG cannot be opened because it is from an unidentified developer" and must manually override via right-click, which most users will not do.

**Fix:** Add two steps to `build_app.sh`:
1. `codesign --deep --force --options runtime --sign "Developer ID Application: ..." ZeroG.app`
2. `xcrun notarytool submit ZeroG.zip --apple-id ... --team-id ... --password ... --wait`, then `xcrun stapler staple ZeroG.app`

Requires an Apple Developer account ($99/yr) and a Developer ID certificate.

---

#### B2 · Missing `NSInputMonitoringUsageDescription` in Info.plist
**Severity:** Blocker | **Category:** macOS Policy  
**Evidence:** Key absent from `Info.plist`. `KeyMonitor.swift:69` installs a `CGEvent` tap on `flagsChanged` + `keyDown`.

macOS 13.6+ requires this key for any app that reads keyboard events globally, even in `.listenOnly` mode. Without it, the permission prompt fails silently or the tap does nothing.

**Fix — add to `Info.plist`:**
```xml
<key>NSInputMonitoringUsageDescription</key>
<string>ZeroG monitors your Control key to detect when to start and stop recording.</string>
```

---

#### B3 · `ptr.baseAddress!` force-unwrap in hot audio path
**Severity:** Blocker | **Category:** Crash risk  
**Evidence:** `AudioRecorder.swift:145` and `:189` — called on every audio buffer (~10×/sec while recording).

```swift
vDSP_svesq(ptr.baseAddress! + idx, ...)   // line 145
vDSP_rmsqv(ptr.baseAddress!, ...)          // line 189
```

The pointer is guaranteed non-nil by the `UnsafeBufferPointer` contract, but a forced unwrap means any lifecycle violation crashes the app mid-recording with no recovery.

**Fix:** Replace with `guard let base = ptr.baseAddress else { return }`.

---

### High Severity — Fix Before First Public Release

#### H1 · Gemini API key stored in UserDefaults, not Keychain
**Severity:** High | **Category:** Security  
**Evidence:** `GeminiService.swift:46`; `StatusBarController.swift:155` pre-fills the key in a plaintext `NSTextField`.

UserDefaults `.plist` files are readable by any process running as the same user. The Keychain is the OS-provided encrypted store for credentials.

**Fix:** Replace `UserDefaults.standard.set/string` with `SecItemAdd` / `SecItemCopyMatching` using service name `"com.zerog.gemini-api-key"`. ~30 lines of standard Swift; no new entitlements needed.

---

#### H2 · No timeout or retry for WhisperKit model download
**Severity:** High | **Category:** Production Readiness  
**Evidence:** `TranscriptionEngine.swift:72` — `WhisperKit.download()` with no timeout, no retry, no cleanup on failure. Model is ~1.5 GB.

On a slow or dropped connection, the app hangs in `.loading` indefinitely. The only recovery is quitting and relaunching.

**Fix:** Wrap the download in a cancellable `Task`. On failure, transition to `.error("Download failed — check connection")` and expose a "Retry" menu item that re-calls `initialize()`.

---

#### H3 · Permission failures are silent at launch
**Severity:** High | **Category:** UX / First-launch  
**Evidence:** `ZeroGApp.swift:65` — `keyMonitor.start()` failure is logged to stdout only. `KeyMonitor.swift:98–109` prints a multi-line explanation users never see.

A user without Input Monitoring or Accessibility permission sees the menu bar icon, holds Control, and nothing happens — no error, no guidance.

**Fix:** At launch, attempt a dummy `CGEvent.tapCreate`; if it returns nil, show a menu item "⚠ Grant Input Monitoring →" that opens:
```swift
NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
```

---

#### H4 · Force-cast in status bar icon update
**Severity:** High | **Category:** Crash risk  
**Evidence:** `StatusBarController.swift:123` — `(image.withSymbolConfiguration(config) ?? image).copy() as! NSImage`

Runs on every state change. Use `as? NSImage ?? image` instead.

---

#### H5 · Floating dependency versions
**Severity:** High | **Category:** Maintainability  
**Evidence:** `Package.swift:14` — `from: "0.9.0"` for WhisperKit, currently resolving to `0.15.0`. A `swift package update` can silently jump to a breaking version.

**Fix:** Pin to `.exact("0.15.0")` for WhisperKit and `.exact("0.5.6")` for GoogleGenerativeAI. Re-pin deliberately when upgrading.

---

### Medium Severity — Fix in Next Release Cycle

#### M1 · Clipboard restore race condition
**Evidence:** `TextInjector.swift:27–42` — snapshot taken, paste fired, restore scheduled 600 ms later. If the user manually pastes something in that 600 ms window, their content is overwritten by the restore.

**Fix:** Check `NSPasteboard.general.changeCount` before restoring. If it has changed since the snapshot, skip the restore — the user intentionally replaced the clipboard.

---

#### M2 · Gemini failures are invisible to the user
**Evidence:** `GeminiService.swift:113–118` — all errors (timeout, auth failure, rate limit, offline) are caught and the original text returned silently with a debug-only log.

**Fix:** Return a typed result (`enum GeminiResult { case polished(String); case fallback(String, Error) }`). Show a subtle "Gemini unavailable" notice in the HUD.

---

#### M3 · No max recording duration cap
**Evidence:** `AudioRecorder.swift:43` — `accumulatedSamples: [Float]` grows without bound. At 16 kHz, 10 min = ~38 MB. `KeyMonitor.swift:39` has a 120 s cap but it is enforced in the key monitor, not the recorder itself.

**Fix:** In `processAudioBuffer`, stop and auto-invoke `stopRecording` when `accumulatedSamples.count > 16_000 * 300` (5 minutes). Show a UI notice.

---

#### M4 · No timeout in `.processing` state
**Evidence:** `AppStateMachine.swift:58–65` — no guard against the app getting stuck in `.processing` if WhisperKit hangs. The user cannot record again.

**Fix:** Start a `DispatchWorkItem` when entering `.processing` that fires after 60 seconds and transitions to `.error("Transcription timed out")`.

---

#### M5 · No onboarding for first-time users
**Evidence:** `StatusBarController.swift` — no first-launch detection. Users must discover three separate permissions, the Gemini key menu, and the hotkey without any in-app guidance.

**Fix:** On first launch (`UserDefaults.standard.bool(forKey: "hasLaunched")`), open a small welcome window listing required permissions, the hotkey, and the optional Gemini setup.

---

#### M6 · No accessibility labels on HUD or menu items
**Evidence:** `HUDPanel.swift` — no `.accessibilityLabel()` or `.accessibilityValue()` on any SwiftUI views. VoiceOver users receive no state feedback during recording, processing, or error states.

---

#### M7 · Privacy manifest not verified
**Evidence:** No `PrivacyInfo.xcprivacy` at the app target level.

**Fix:** Run `find ZeroG.app -name PrivacyInfo.xcprivacy` on the built bundle. If the clipboard API (`NSPasteboard`) is flagged under Apple's required-reasons list, add an app-level manifest declaring `NSPrivacyAccessedAPICategoryPasteboardRead` with reason `C56D.1`.

---

### Low Severity / Follow-up

| # | Issue | File | Fix |
|---|---|---|---|
| L1 | Version number hardcoded in `Info.plist`, no release process | `Info.plist:26` | Read from a `VERSION` file in `build_app.sh` |
| L2 | Gemini model hardcoded as `"gemini-2.0-flash-exp"` (experimental) | `GeminiService.swift:24` | Move to `Config.swift`; switch to a stable model name when available |
| L3 | Max recording timeout (120 s) hardcoded | `KeyMonitor.swift:39` | Move to `Config.swift` |
| L4 | Gemini prompt has no guidance for non-English or technical content | `gemini_prompt.txt` | Add: "If input is in a non-English language, return it unchanged. Preserve URLs, code, and proper nouns exactly." |
| L5 | `GeminiService` singleton requires implicit `configure()` before use | `GeminiService.swift` | Guard at call site or make initialization explicit |
| L6 | Debug log at `GeminiService.swift:105` logs first 60 chars of polished text | `GeminiService.swift:105` | Remove or hash — transcribed speech is personal data |
| L7 | No localization infrastructure | all UI files | Add `NSLocalizedString` wrappers if international distribution is planned |
| L8 | No tests for `AudioRecorder`, `KeyMonitor`, or `TextInjector` | test suite | High-value: `trimTrailingSilence`, clipboard snapshot/restore, keycode detection |

---

## If Mac App Store Submission Is Ever Pursued

The fundamental blockers are two capabilities incompatible with the App Store sandbox:

1. **`CGEvent.tapCreate(.cgSessionEventTap)`** — global keyboard monitoring. Sandboxed apps cannot install a system-wide event tap.
2. **`CGEvent.post(tap: .cgSessionEventTap)`** — synthetic keyboard events for Cmd+V injection.

Both would need to be replaced:

- **Key monitoring → `NSEvent.addGlobalMonitorForEvents(matching:)`** — works in sandboxed apps with the Accessibility entitlement (already declared). This is the approved App Store pattern.
- **Text injection → Accessibility API (`AXUIElementSetAttributeValue`)** — inserts text into the focused element directly, bypassing the clipboard. Requires the Accessibility entitlement (already declared). Trade-off: apps that do not expose an accessibility interface (some Electron apps, games) will not work.

This refactor is substantial but not architecturally complex. Treat it as a V2 goal if App Store distribution becomes a priority.

Additionally for App Store submission:
- Re-enable the sandbox (`com.apple.security.app-sandbox = true`) in `ZeroG.entitlements`
- Add `NSInputMonitoringUsageDescription` (required regardless of distribution channel on macOS 13.6+)
- Verify all dependency privacy manifests are bundled in the `.app`

---

## Component Risk Summary

| Component | File | Risk Level | Key Issue |
|---|---|---|---|
| `KeyMonitor` | `ZeroG/Core/KeyMonitor.swift` | High | Silent failure if permissions denied |
| `AudioRecorder` | `ZeroG/Core/AudioRecorder.swift` | High | Force-unwrap crash + unbounded memory |
| `TextInjector` | `ZeroG/Core/TextInjector.swift` | Medium | Clipboard race condition; no write error check |
| `TranscriptionEngine` | `ZeroG/Core/TranscriptionEngine.swift` | Medium | No download timeout/retry |
| `GeminiService` | `ZeroG/Core/GeminiService.swift` | Medium | Plaintext key storage; silent failure |
| `AppStateMachine` | `ZeroG/Core/AppStateMachine.swift` | Medium | No processing timeout |
| `StatusBarController` | `ZeroG/GUI/StatusBarController.swift` | Low | Force-cast; no accessibility labels |
| `HUDPanel` | `ZeroG/GUI/HUDPanel.swift` | Low | No accessibility labels |
| `build_app.sh` | `ZeroGSwift/build_app.sh` | High | No signing or notarization |
| `Info.plist` | `ZeroGSwift/Info.plist` | Blocker | Missing `NSInputMonitoringUsageDescription` |
| `ZeroG.entitlements` | `ZeroG/Resources/ZeroG.entitlements` | Blocker | Sandbox disabled (incompatible with App Store) |
| `Package.swift` | `ZeroGSwift/Package.swift` | High | Floating dependency versions |
