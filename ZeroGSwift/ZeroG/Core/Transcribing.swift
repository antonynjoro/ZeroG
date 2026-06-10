import Foundation

// MARK: - Transcribing

/// Common surface for a speech-to-text engine, so the rest of the app (AudioRecorder,
/// AppDelegate) can drive any backend without knowing which one it is.
///
/// Introduced for the FluidAudio/Parakeet spike (`spike/fluidaudio-parakeet`) so the
/// existing WhisperKit engine and a parallel Parakeet engine can be A/B-compared behind
/// one interface. `TranscriptionEngine` (WhisperKit) already matched this shape exactly;
/// conformance adds no behavior. See docs/spikes/fluidaudio-parakeet-spike.md.
///
/// The audio contract is identical for every backend: a 16 kHz mono `[Float]` buffer
/// (the same array `AudioRecorder` already produces).
protocol Transcribing: AnyObject {
    /// Status updates during model download / load, surfaced to the loading HUD.
    var onStatusUpdate: ((String) -> Void)? { get set }

    /// Download (if needed) and load the model into memory. Idempotent.
    func initialize() async throws

    /// Transcribe a 16 kHz mono float buffer to text.
    func transcribe(_ audioArray: [Float]) async throws -> String

    /// Release the model to free memory.
    func unloadModel()
}
