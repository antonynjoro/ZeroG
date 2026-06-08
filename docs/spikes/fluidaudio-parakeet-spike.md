# Spike: FluidAudio (Parakeet) vs WhisperKit for ZeroG STT

> Living doc — the cross-session source of truth for this spike. Update the **Status**,
> **Findings**, and **Decision log** as work proceeds. Branch: `spike/fluidaudio-parakeet`.

## Status

| Date | State | Note |
|------|-------|------|
| 2026-06-07 | in-progress | Branch + doc created. Swift 6.3.2 preflight passed. Scaffolding underway. |

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

## Open questions / next-session pickup

- Verify exact FluidAudio ASR API against the resolved checkout before writing the wrapper
  (`AsrModels` / `AsrManager` / result text property — plan snippets are guesses).
- Confirm Parakeet v2 vs v3 variant identifiers in FluidAudio.
- Measurement is a HANDOFF: needs the user's voice recordings — cannot be done by the model.
- If adopted later: delete Whisper engine + cleanup stack + `TranscriptionQuality`, drop
  WhisperKit dep, re-notarize, and seed the still-open audio-fixture regression harness.
