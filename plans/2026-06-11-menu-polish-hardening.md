---
status: in-progress
created: 2026-06-11
branch: feature/menu-cleanup-and-hardening (off dev)
---

# Menu cleanup · on-device Polish (Apple Foundation Models) · hardening

## Context

Post-onboarding/DMG, the menu still carries FluidAudio-spike testing tools and a
cloud-Gemini polish path that (a) contradicts the "audio never leaves your Mac"
promise by sending transcribed **text** to Google, and (b) is triggered by
hold-trigger-key **+ Q**, which silently breaks when the trigger key is Fn/Globe
(Fn isn't a real modifier, so the Q keyDown the tap relies on never arrives).

Decision (confirmed with Antony, 2026-06-11): go **fully on-device**. Replace
cloud Gemini with **Apple Foundation Models** (the system on-device ~3B LLM
behind Apple Intelligence; `import FoundationModels`). Decouple polish from
recording — invoke it as a **menu item** and a **configurable global shortcut**
that polishes the last transcription, shows the HUD, and pastes the result.

### Locked decisions
- **Engine:** Apple Foundation Models only. No cloud, no downloaded MLX model.
- **Unsupported Macs (macOS <26 / non-Apple-Intelligence):** show the polish UI
  **disabled with a reason** ("Polish needs macOS 26 + Apple Intelligence") — not
  hidden. Plain dictation works everywhere as today.
- **Trigger:** a menu item ("Copy Polished Version") **and** a **configurable**
  global keyboard shortcut (set from onboarding + menu) → polish last
  transcription → HUD "Polishing…" → paste into the focused field.
- **Spike menu items removed entirely** (STT backend picker + Compare Backends).
- **One branch, plan-first.** Hardening rides along: force-unwrap guards,
  model-download timeout + user-facing retry, About + version.
- Min deployment target **stays macOS 14**. All Foundation Models code sits
  behind `@available(macOS 26, *)` + runtime availability checks.

## Hard constraints / gotchas

- **Foundation Models requires macOS 26 (Tahoe) + Apple Silicon + Apple
  Intelligence enabled.** Gate every call with `if #available(macOS 26, *)` and
  check `SystemLanguageModel.default.availability` at runtime
  (`.available` vs `.unavailable(reason)` — reasons include deviceNotEligible,
  appleIntelligenceNotEnabled, modelNotReady). Dev Mac is on Tahoe (Darwin 25.4),
  so this is testable locally.
- **No `import FoundationModels` at file scope on a macOS 14 build** would fail —
  but the framework is weak-linked and the symbols only referenced inside
  `@available` blocks, so a single file `PolishService.swift` with availability
  guards compiles against the 14 target. Verify it builds AND runs on 14 (feature
  reports unavailable) before shipping.
- **Polish targets `stateMachine.lastTranscription`** (already stored). Paste
  reuses `TextInjector.injectText` → same `AXIsProcessTrusted()` preflight and
  `.needsPermission` fallback as dictation.
- **Global polish shortcut** = a real chord the dead-simple +Q couldn't be.
  Reuse the existing listen-only CGEvent tap in `KeyMonitor` (it already watches
  keyDown) to detect a configurable (keyCode + modifierFlags) chord. Store it in
  `Config` (UserDefaults). Capture UI = a "press your shortcut" recorder in the
  onboarding step and a menu "Change Polish Shortcut…".
- **Removing cloud Gemini touches several files** — `useGemini` is woven through
  AppStateMachine (session flag), KeyMonitor (the +Q detection), AudioRecorder
  (passes the flag), StatePresentation (polish-violet visuals), StatusBarController
  (key dialog + menu item), Config (`googleAPIKey*`), GeminiService. Recording
  becomes always-plain-Parakeet; polish is a separate post-hoc action. Delete the
  stored Gemini key from UserDefaults on launch (one-time cleanup). The
  `gemini_prompt.txt` resource is repurposed as the polish system prompt
  (rename → `polish_prompt.txt`).
- **`.polishing` is a new lingering-ish state** (like processing but for the
  post-hoc polish flow): show the HUD, then → success → idle. Update every
  exhaustive switch (AppState, StatePresentation, HUD, statusText, isReady).

## Work breakdown (commits)

1. **plan doc** (this file).
2. **refactor(menu): remove FluidAudio-spike menu tooling** — drop the STT-backend
   picker submenu + "Compare STT Backends" item, the `onRunBackendComparison`
   plumbing (StatusBarController + ZeroGApp), and `BackendComparator`. Keep
   `Config.STTBackend`/`sttBackend` (still selects the engine; default parakeetV3).
   `WERCalculator` stays (has tests) but is now unused by the app — leave or note.
3. **refactor(gemini): remove the cloud Gemini polish path** — delete the +Q /
   `useGemini` machinery (KeyMonitor, AppStateMachine session flag, AudioRecorder,
   StatePresentation polish visuals), the "Set Gemini API Key" menu item + dialog,
   `Config.googleAPIKey*`, and `GeminiService`. One-time delete of the stored key.
   Recording is now always plain. Rename `gemini_prompt.txt` → `polish_prompt.txt`.
   Update tests that reference useGemini / Gemini.
4. **feat(polish): PolishService on Apple Foundation Models** — `PolishService`
   with `@available(macOS 26, *)` core + a non-availability-gated façade exposing
   `isAvailable`, `unavailableReason`, and `polish(_:) async throws -> String`.
   Loads the polish system prompt. Unit-testable seam (protocol) where practical.
5. **feat(state): `.polishing` HUD state** — add the state + presentation +
   switches + tests.
6. **feat(menu): Polish menu items + About** — "Copy Polished Version" (polish
   `lastTranscription` → clipboard; disabled w/ reason when unavailable or no last
   transcription), and the restructured clean menu. Add "About ZeroG" (version
   from Info.plist). 
7. **feat(hotkey): configurable global Polish shortcut** — `Config` stores the
   chord; `KeyMonitor` detects it on the existing tap; firing → polish
   `lastTranscription` → `.polishing` HUD → `TextInjector` paste (AX preflight +
   `.needsPermission` fallback reused). Menu "Change Polish Shortcut…" recorder.
8. **feat(onboarding): skippable Polish step** — new step after Trigger key,
   before Done: "Polish your text on-device with Apple Intelligence" → Enable
   (capture the shortcut) / Skip. Disabled-with-reason when unavailable. Update the
   step machine + progress count + re-entry/tests.
9. **fix(audio): safe pointer access** — replace the two `ptr.baseAddress!` with
   `guard let base = ptr.baseAddress else { return }`.
10. **feat(resilience): model-download timeout + user-facing retry** — add a hard
    timeout around `AsrModels.downloadAndLoad`; on terminal failure surface a
    retry affordance (HUD/menu) instead of a dead "Model Failed" needing relaunch.

Each commit: `swift test` green; app-affecting → `build_app.sh` + relaunch.

## Final menu (public)

```
Ready — Hold ⌃ to record            (status, live)
[Hotkey disabled — open Setup]      (only when Accessibility missing)
──────────
Setup & Permissions…
Record Key ▸                         (Left Control … Fn/Globe)
──────────
Copy Last Transcription              (enabled when available)
Copy Polished Version                (on-device; disabled w/ reason if unavailable)
Change Polish Shortcut…
──────────
About ZeroG                          (version)
Quit ZeroG
```
(STT backend picker, Compare Backends, and Gemini key items are gone.)

## Out of scope
- Per-app polish styles / prompt customization (later).
- Streaming polish output into the field (paste the finished result).
