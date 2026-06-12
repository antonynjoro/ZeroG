import Foundation
import FluidAudio

// MARK: - Parakeet Transcription Engine (FluidAudio spike)

/// Wraps FluidAudio's NVIDIA Parakeet TDT CoreML models on the Apple Neural Engine.
/// SPIKE ONLY (`spike/fluidaudio-parakeet`) — a parallel `Transcribing` implementation to
/// A/B against WhisperKit on the same audio. See docs/spikes/fluidaudio-parakeet-spike.md.
///
/// Deliberately runs NO trailing-hallucination cleanup: a transducer like Parakeet is far
/// less prone to the silence caption-isms Whisper produces, and measuring whether it
/// hallucinates at all is part of the spike. Batch mode only — FluidAudio's streaming
/// `SlidingWindowAsrManager` is intentionally not used (push-to-talk is short and bounded).
///
/// API verified against FluidAudio 0.15.2 source:
///   `AsrModels.downloadAndLoad(version:progressHandler:)`, `AsrManager(config:models:)`,
///   `transcribe(_:decoderState:language:) -> ASRResult`, `ASRResult.text`.
final class ParakeetTranscriptionEngine: Transcribing {

    /// Which Parakeet variant to load.
    enum Variant {
        case v2 // English-only (parakeet-tdt-0.6b-v2)
        case v3 // Multilingual (parakeet-tdt-0.6b-v3)

        var asrVersion: AsrModelVersion { self == .v2 ? .v2 : .v3 }
        var label: String { self == .v2 ? "Parakeet v2 (English)" : "Parakeet v3 (multilingual)" }
    }

    private let variant: Variant
    private var manager: AsrManager?
    private var models: AsrModels?
    private var isInitialized = false

    var onStatusUpdate: ((String) -> Void)?

    init(variant: Variant) {
        self.variant = variant
    }

    // MARK: Initialization

    func initialize() async throws {
        guard !isInitialized else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        Log.debug("Parakeet", "Attempting model load: \(variant.label)")

        do {
            reportStatus("Downloading \(variant.label)...")

            // Download + load, with one retry on transient failure and a hard
            // timeout so a hung/stalled download surfaces as a retryable error
            // instead of spinning on "Downloading…" forever.
            let label = variant.label
            let version = variant.asrVersion
            let loaded = try await Self.withTimeout(seconds: Self.downloadTimeout) {
                try await Self.withOneRetry {
                    try await AsrModels.downloadAndLoad(
                        version: version,
                        progressHandler: { [weak self] progress in
                            let pct = Int(progress.fractionCompleted * 100)
                            self?.reportStatus("Downloading \(label): \(pct)%")
                        }
                    )
                }
            }

            reportStatus("Loading model into memory...")
            let mgr = AsrManager(config: .default, models: loaded)

            self.models = loaded
            self.manager = mgr
            self.isInitialized = true

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            Log.debug("Parakeet", "✅ \(variant.label) loaded in \(String(format: "%.1f", duration))s")
            reportStatus("Ready!")
        } catch {
            Log.error("Parakeet", "❌ \(variant.label) failed: \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: Transcription

    func transcribe(_ audioArray: [Float]) async throws -> String {
        guard let manager, let models else {
            throw TranscriptionError.notInitialized
        }
        guard !audioArray.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        // Fresh decoder state per push-to-talk utterance (no cross-utterance carryover).
        var state = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
        let result = try await manager.transcribe(audioArray, decoderState: &state)

        // Parakeet is verbatim by training ("um"/"uh" kept); strip fillers in the text
        // domain. Whisper needs no equivalent — its caption-trained decoder self-cleans.
        return DisfluencyFilter.clean(result.text)
    }

    // MARK: Teardown

    func unloadModel() {
        manager = nil
        models = nil
        isInitialized = false
        Log.debug("Parakeet", "Model unloaded.")
    }

    // MARK: - Private

    private func reportStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusUpdate?(message)
        }
    }

    /// Run `op`; on failure, wait briefly and try exactly once more.
    private static func withOneRetry<T>(_ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch {
            Log.error("Parakeet", "Load failed (\(error.localizedDescription)); retrying once...")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return try await op()
        }
    }

    /// Total seconds allowed for the first-launch model download + load before we
    /// give up and surface a retryable error.
    private static let downloadTimeout: Double = 180

    /// Run `op` with a hard deadline. Whichever finishes first wins; the loser is
    /// cancelled. A timeout throws a transcription error the caller can retry.
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ op: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TranscriptionError.transcriptionFailed("Model download timed out")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
