# Spike: FluidAudio (Parakeet) vs WhisperKit for ZeroG STT

> Living doc — the cross-session source of truth for this spike. Update the **Status**,
> **Findings**, and **Decision log** as work proceeds. Branch: `spike/fluidaudio-parakeet`.

## Status

| Date | State | Note |
|------|-------|------|
| 2026-06-07 | in-progress | Branch + doc created. Swift 6.3.2 preflight passed. Scaffolding underway. |
| 2026-06-07 | blocked (handoff) | All spike code landed (engine, factory, comparator, menu, tests). Build + 58 tests green; unsigned .app built. BLOCKED on user voice recordings — measurement cannot proceed without them. |
| 2026-06-07 | decided (adopt) | User judged both Parakeet variants fine on their voice. DECISION: adopt **Parakeet v3** as the single engine; remove the picker AND WhisperKit entirely. Decided on qualitative feel (no WER numbers captured). Live default flipped to v3 for a real-world soak; Whisper deletion staged as a follow-up after soak. |
| 2026-06-07 | soaking (v3 default) | Running live on v3 as default. User reports it "feels like it's going pretty well" in real push-to-talk use; **soak ongoing — not yet greenlit for Whisper deletion**. All work committed on branch `spike/fluidaudio-parakeet` (6 commits), NOT pushed. |
| 2026-06-09 | soaking — ⚠️ findings | Two soak findings: (1) v3 keeps "um"/"uh" verbatim — user now wants them cleaned (Whisper did this inherently). (2) **Word misrecognition observed in real dictation: "sentences" → "sentises"** — this is rubric criterion #1 (accent-word accuracy ≤ Whisper) territory. One word ≠ verdict, but Whisper deletion stays blocked until accuracy is compared on the problem words. |
| 2026-06-09 | soaking + filler filter | `DisfluencyFilter` added (user greenlit): bounded text-domain pass on Parakeet output only — whole-token match against a fixed filler list, repairs capital/terminal-punctuation seams it creates, cannot misspell/reorder/invent. 11 tests; suite 69 green. Soak continues with cleaned output. Misrecognition concern still open. |
| 2026-06-09 | soaking — ✅ positive | First post-filter real dictation: long multi-sentence paragraph, zero fillers in output, clean punctuation, no misrecognitions. User: "It did a great job." Soak trending toward greenlight; keep watching for accent fumbles. |

States: `not-started` / `in-progress` / `blocked` / `decided`.

## Why this spike exists

ZeroG uses WhisperKit (`large-v3-v20240930_turbo`), chosen because it handles the user's
Kenyan accent (`base`/`small` failed). Whisper's costs: inference-dominated latency, and
silence hallucination ("thank you / please subscribe") that forces the entire
`cleanTranscript`/`collapseRepetitions`/`noSpeechProb` stack in `TranscriptionEngine.swift`.

**FluidAudio** (Apache 2.0, SPM, active — v0.15.2, 2026-06-07) wraps NVIDIA **Parakeet TDT**
CoreML on the ANE. Promise: 110–300× RTFx (vs ~real-time), ~66 MB working set (vs ~1–2 GB),
and — being a *transducer*, not a caption-trained autoregressive decoder — likely little/no
silence hallucination (could delete the cleanup stack). macOS 14.0 min (matches our target).

The single deciding unknown: **accent accuracy on the user's actual voice.** Parakeet trained
on cleaner/narrower (European + read) corpora than Whisper's 680k hrs of diverse web audio.
Published LibriSpeech WER does NOT predict Kenyan-accent performance. Must be measured.

## Hypothesis & pre-registered decision rubric (written BEFORE any data)

**Hypothesis**: Parakeet is much faster and hallucination-free, but may regress on the user's
accent. Worth adopting only if accuracy holds.

**Adopt Parakeet ONLY if ALL hold on the user's own recordings:**
- [ ] Accent-word WER ≤ Whisper's (words Whisper gets right today stay right).
- [ ] No regression on long-form (>30 s run-on) — no boundary truncation.
- [ ] Warm-median latency strictly better than Whisper (else accuracy risk buys nothing).

Else: keep Whisper, delete the spike code, keep this doc with the recorded "no".
A documented "no" is a successful spike.

## Architecture of the spike (additive, default unchanged)

- `Transcribing` protocol (`ZeroG/Core/Transcribing.swift`) — common surface.
- `TranscriptionEngine` conforms (Whisper, unchanged, remains DEFAULT).
- `ParakeetTranscriptionEngine` (`ZeroG/Core/ParakeetTranscriptionEngine.swift`) — FluidAudio.
- `Config.STTBackend { whisper, parakeetV2, parakeetV3 }`, default `.whisper`, UserDefaults key
  `"STTBackend"`. Lazy factory in `ZeroGApp` loads only the selected backend.
- `WERCalculator` — pure word-level Levenshtein, for objective scoring.
- Dual-transcribe debug: one menu-bar item runs both backends on the SAME captured buffer,
  logs transcripts + cold/warm-median latency. Gemini OFF during measurement.
- Streaming (`SlidingWindowAsrManager`) intentionally NOT used — push-to-talk is short/bounded.

## Findings (fill in from real runs — do NOT fabricate)

Test script per clip type. Reference = ground-truth of what was actually said.

| Clip | Backend | WER | Cold latency | Warm-median latency | Hallucination? | Notes |
|------|---------|-----|--------------|---------------------|----------------|-------|
| normal sentences | whisper |  |  |  |  |  |
| normal sentences | parakeetV2 |  |  |  |  |  |
| normal sentences | parakeetV3 |  |  |  |  |  |
| accent-heavy words | whisper |  |  |  |  |  |
| accent-heavy words | parakeetV2 |  |  |  |  |  |
| accent-heavy words | parakeetV3 |  |  |  |  |  |
| long run-on (>30s) | whisper |  |  |  |  |  |
| long run-on (>30s) | parakeetV2 |  |  |  |  |  |
| long run-on (>30s) | parakeetV3 |  |  |  |  |  |
| trailing silence | whisper |  |  |  |  |  |
| trailing silence | parakeetV2 |  |  |  |  |  |
| trailing silence | parakeetV3 |  |  |  |  |  |

## Decision log (append-only)

- **2026-06-07** — Spike opened. Plan approved. Whisper-vs-Parakeet research: Parakeet ~110–300×
  RTFx, ~66 MB, transducer (low hallucination risk), macOS 14 min, Apache 2.0. Accent accuracy
  is the open question. Branch + doc created; preflight Swift 6.3.2 OK.
- **2026-06-07** — Code complete. Added `Transcribing` protocol (Whisper conforms, unchanged),
  `ParakeetTranscriptionEngine` (FluidAudio 0.15.2 — `AsrModels.downloadAndLoad(version:)`,
  `AsrManager(config:models:)`, `transcribe(_:decoderState:) -> ASRResult`; v2/v3; no cleanup
  pass), `Config.STTBackend` + launch-time factory (only selected backend loads), `WERCalculator`
  (pure Levenshtein), and `BackendComparator` (same buffer → all 3 backends, cold/warm-median
  latency, logs to `~/zerog-backend-comparison.log`). Menu: "STT Backend (spike)" submenu +
  "Compare STT Backends". 17 new tests; full suite 58 green; unsigned `.app` builds. Whisper
  remains the default. **Next: user records the script; run Compare; fill the findings table.**
- **2026-06-07** — DECISION (adopt, single engine). User tested both Parakeet variants live and
  judged them fine. Chose **Parakeet v3** (highest coverage — 25 languages, broadest training,
  better bet for Kenyan accent; FluidAudio's own default) over v2 (English-only, marginally lower
  clean-English WER on a distribution that isn't ours). Chose to remove the picker AND WhisperKit
  entirely (leanest: one engine, one dep, no config surface) rather than keep a DEBUG-gated picker.
  Tradeoff accepted: decided on qualitative feel, no WER numbers captured. Disfluencies ("um"/"ah")
  are kept verbatim by Parakeet — user OK with that; strip later in the text domain or via the
  existing Gemini polish if wanted, NOT by model choice. **Staging:** live default flipped to v3
  now for a real-world soak; Whisper + cleanup stack + picker + comparator + WERCalculator deletion
  is the next step, after the soak confirms v3 holds up in daily push-to-talk use.

## Open questions / next-session pickup

**RESUME HERE (as of 2026-06-07):** Decision is made — adopt **Parakeet v3**, single engine,
no picker. App's live default is already v3. User is **soaking** (daily push-to-talk on v3);
early feel is positive. Branch `spike/fluidaudio-parakeet`, 6 commits, **not pushed**, working
tree clean.

**Next action, once the user greenlights after the soak — the staged Whisper-removal cleanup
(one commit):**
1. Delete `TranscriptionEngine.swift` (Whisper) + its hallucination-cleanup stack
   (`cleanTranscript`, `collapseRepetitions`, `isTrailingHallucination`) and
   `TranscriptionEngineTests.swift`.
2. Delete the picker: `Config.STTBackend` enum + `sttBackend`/`setSTTBackend`,
   `Config.whisperModel`, `Config.TranscriptionQuality`; the "STT Backend (spike)" submenu +
   `backendSelected` + the "Compare STT Backends" item + `runBackendComparison` in
   `StatusBarController`/`AppDelegate`.
3. Delete `BackendComparator.swift`, `WERCalculator.swift`, `WERCalculatorTests.swift`, and the
   `onCapturedAudio` hook in `AudioRecorder` + `lastCapturedBuffer` in `AppDelegate`.
4. Make Parakeet the only engine: either keep the `Transcribing` protocol with
   `ParakeetTranscriptionEngine` as sole conformer (cheap, future-proof) OR collapse the protocol
   and rename `ParakeetTranscriptionEngine` → `TranscriptionEngine`. Update `TranscribingTests`
   (`MockTranscriber`) accordingly.
5. Drop the WhisperKit dependency from `Package.swift`; `swift package resolve`.
6. `swift test` green → `./build_app.sh` → then re-notarize for a release candidate.

**Other follow-ups:**
- Disfluencies ("um"/"ah") kept verbatim by Parakeet — user OK so far. If stripping wanted: do it
  in the text domain (deterministic list) or via the existing Gemini polish, NOT by model choice.
- Capture real WER numbers via `~/zerog-backend-comparison.log` if you ever want the decision
  data-backed (currently decided on feel).
- Note: this removes the WhisperKit model-download timeout/retry audit blocker by removing Whisper;
  Parakeet has its own download retry already.
- Revisit the still-open audio-fixture regression harness (record WAVs + golden transcripts) now
  that the engine is changing.
