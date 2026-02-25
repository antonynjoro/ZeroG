import Foundation
import WhisperKit

// MARK: - Transcription Errors

enum TranscriptionError: LocalizedError {
    case notInitialized
    case emptyAudio
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized: return "WhisperKit model not loaded"
        case .emptyAudio: return "No audio to transcribe"
        case .transcriptionFailed(let reason): return "Transcription failed: \(reason)"
        }
    }
}

// MARK: - Transcription Engine

/// Wraps WhisperKit for on-device speech-to-text using Apple Silicon Neural Engine.
/// Replaces Python's `mlx_whisper.transcribe()` with a native Swift implementation.
///
/// ## Model
/// Uses `openai/whisper-large-v3-turbo` by default — best accuracy/speed tradeoff on M1.
/// WhisperKit automatically routes inference to the Neural Engine (ANE) for maximum throughput.
///
/// ## Performance
/// - ~50× real-time on M1 with large-v3-turbo
/// - Up to 72× real-time on M2 Ultra (GPU+ANE)
/// - Zero-copy audio buffer handling
final class TranscriptionEngine {
    
    // MARK: Configuration
    
    /// The Whisper model variant to use. Turbo models offer the best latency.
    private let modelName: String
    
    // MARK: WhisperKit Instance
    
    private var whisperKit: WhisperKit?
    private var isInitialized = false
    
    /// Serial queue to protect WhisperKit access from concurrent calls.
    private let transcriptionQueue = DispatchQueue(label: "com.zerog.transcription", qos: .userInitiated)
    
    // MARK: Initialization
    
    /// Ordered list of model names to try (best → most compatible).
    private static let modelFallbackChain = [
        "large-v3-v20240930_turbo",  // Best speed/accuracy on M1
        "large-v3",                   // High accuracy fallback
        "base.en",                    // Fast, English-only fallback
    ]
    
    init(modelName: String? = nil) {
        self.modelName = modelName ?? Self.modelFallbackChain[0]
    }
    
    /// Load the WhisperKit model. Call once at app startup.
    /// Tries models in fallback order until one succeeds.
    func initialize() async throws {
        guard !isInitialized else { return }
        
        let modelsToTry: [String]
        if Self.modelFallbackChain.contains(modelName) {
            // Start from the requested model in the chain
            let idx = Self.modelFallbackChain.firstIndex(of: modelName) ?? 0
            modelsToTry = Array(Self.modelFallbackChain[idx...])
        } else {
            modelsToTry = [modelName] + Self.modelFallbackChain
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[TranscriptionEngine] Attempting model load. Chain: \(modelsToTry)")
        #endif
        
        var lastError: Error?
        for model in modelsToTry {
            do {
                print("[TranscriptionEngine] Trying model: \(model)...")
                whisperKit = try await WhisperKit(model: model, verbose: true)
                isInitialized = true
                print("[TranscriptionEngine] ✅ Model loaded: \(model)")
                break
            } catch {
                print("[TranscriptionEngine] ❌ Model '\(model)' failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        guard isInitialized else {
            throw lastError ?? TranscriptionError.transcriptionFailed("No compatible model found")
        }
        
        #if DEBUG
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("[TranscriptionEngine] Model loaded in \(String(format: "%.2f", duration))s")
        #endif
        
        // Warmup: run a dummy transcription to prime Metal/ANE pipelines
        try await warmup()
    }
    
    /// Transcribe a float audio buffer (16kHz mono) to text.
    ///
    /// - Parameter audioArray: Raw audio samples at 16kHz, mono, Float32.
    /// - Returns: The transcribed text string.
    func transcribe(_ audioArray: [Float]) async throws -> String {
        guard let kit = whisperKit else {
            throw TranscriptionError.notInitialized
        }
        
        guard !audioArray.isEmpty else {
            throw TranscriptionError.emptyAudio
        }
        
        let results = try await kit.transcribe(audioArray: audioArray)
        
        // Combine all segment texts
        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    /// Unload the model to free memory after extended inactivity.
    func unloadModel() {
        whisperKit = nil
        isInitialized = false
        
        #if DEBUG
        print("[TranscriptionEngine] Model unloaded.")
        #endif
    }
    
    // MARK: - Private
    
    /// Prime the model with a silent audio buffer to eliminate first-transcription cold start.
    private func warmup() async throws {
        let silentAudio = [Float](repeating: 0.0, count: 16_000) // 1 second of silence
        _ = try? await transcribe(silentAudio)
        
        #if DEBUG
        print("[TranscriptionEngine] Warmup complete.")
        #endif
    }
}
