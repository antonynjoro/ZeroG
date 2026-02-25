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
actor TranscriptionEngine {
    
    // MARK: Configuration
    
    /// The Whisper model variant to use. Turbo models offer the best latency.
    private let modelName: String
    
    // MARK: WhisperKit Instance
    
    private var whisperKit: WhisperKit?
    private var isInitialized = false
    
    // MARK: Initialization
    
    init(modelName: String = "large-v3-turbo") {
        self.modelName = modelName
    }
    
    /// Load the WhisperKit model. Call once at app startup.
    /// This downloads and compiles the model for the current device's Neural Engine.
    func initialize() async throws {
        guard !isInitialized else { return }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[TranscriptionEngine] Loading WhisperKit model: \(modelName)...")
        #endif
        
        let config = WhisperKitConfig(
            model: modelName,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false
        )
        
        whisperKit = try await WhisperKit(config)
        isInitialized = true
        
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
        
        let results = try await kit.transcribe(
            audioArray: audioArray,
            decodeOptions: DecodingOptions(
                language: "en",
                usePrefillPrompt: true
            )
        )
        
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
        _ = try await transcribe(silentAudio)
        
        #if DEBUG
        print("[TranscriptionEngine] Warmup complete.")
        #endif
    }
}
