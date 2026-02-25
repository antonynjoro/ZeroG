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
final class TranscriptionEngine {
    
    // MARK: Configuration
    
    private let modelName: String
    
    // MARK: WhisperKit Instance
    
    private var whisperKit: WhisperKit?
    private var isInitialized = false
    
    /// Serial queue to protect WhisperKit access.
    private let transcriptionQueue = DispatchQueue(label: "com.zerog.transcription", qos: .userInitiated)
    
    /// Callback for status updates during initialization (download progress, model loading phases).
    var onStatusUpdate: ((String) -> Void)?
    
    // MARK: Model Fallback
    
    private static let modelFallbackChain = [
        "large-v3-v20240930_turbo",
        "large-v3",
        "base.en",
    ]
    
    // MARK: Initialization
    
    init(modelName: String? = nil) {
        self.modelName = modelName ?? Self.modelFallbackChain[0]
    }
    
    /// Load the WhisperKit model with progress reporting.
    func initialize() async throws {
        guard !isInitialized else { return }
        
        let modelsToTry: [String]
        if Self.modelFallbackChain.contains(modelName) {
            let idx = Self.modelFallbackChain.firstIndex(of: modelName) ?? 0
            modelsToTry = Array(Self.modelFallbackChain[idx...])
        } else {
            modelsToTry = [modelName] + Self.modelFallbackChain
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        print("[TranscriptionEngine] Attempting model load. Chain: \(modelsToTry)")
        
        var lastError: Error?
        for model in modelsToTry {
            do {
                print("[TranscriptionEngine] Trying model: \(model)...")
                reportStatus("Downloading model: \(model)...")
                
                // Step 1: Download the model with progress reporting
                let modelFolder = try await WhisperKit.download(
                    variant: model,
                    progressCallback: { [weak self] progress in
                        let pct = Int(progress.fractionCompleted * 100)
                        let message = "Downloading model: \(pct)%"
                        self?.reportStatus(message)
                        print("[TranscriptionEngine] \(message)")
                    }
                )
                
                reportStatus("Loading model into memory...")
                print("[TranscriptionEngine] Download complete. Loading from: \(modelFolder.path)")
                
                // Step 2: Initialize WhisperKit with the downloaded model folder
                let config = WhisperKitConfig(
                    modelFolder: modelFolder.path,
                    computeOptions: ModelComputeOptions(
                        audioEncoderCompute: .cpuAndNeuralEngine,
                        textDecoderCompute: .cpuAndNeuralEngine
                    ),
                    verbose: true,
                    prewarm: false,
                    load: false,
                    download: false
                )
                
                let kit = try await WhisperKit(config)
                
                // Set up model state callback for loading phases
                kit.modelStateCallback = { [weak self] oldState, newState in
                    let phase: String
                    switch newState {
                    case .loading:
                        phase = "Loading neural network..."
                    case .prewarming:
                        phase = "Warming up Neural Engine..."
                    case .loaded:
                        phase = "Model ready!"
                    case .prewarmed:
                        phase = "Neural Engine warmed up"
                    default:
                        phase = "Preparing model..."
                    }
                    self?.reportStatus(phase)
                    print("[TranscriptionEngine] Model state: \(oldState) → \(newState)")
                }
                
                // Step 3: Load models into memory
                reportStatus("Compiling for Neural Engine...")
                try await kit.loadModels()
                
                whisperKit = kit
                isInitialized = true
                
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                print("[TranscriptionEngine] ✅ Model '\(model)' loaded in \(String(format: "%.1f", duration))s")
                reportStatus("Ready!")
                break
                
            } catch {
                print("[TranscriptionEngine] ❌ Model '\(model)' failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        
        guard isInitialized else {
            throw lastError ?? TranscriptionError.transcriptionFailed("No compatible model found")
        }
    }
    
    /// Transcribe a float audio buffer (16kHz mono) to text.
    func transcribe(_ audioArray: [Float]) async throws -> String {
        guard let kit = whisperKit else {
            throw TranscriptionError.notInitialized
        }
        
        guard !audioArray.isEmpty else {
            throw TranscriptionError.emptyAudio
        }
        
        let results = try await kit.transcribe(audioArray: audioArray)
        
        let text = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    /// Unload the model to free memory.
    func unloadModel() {
        whisperKit = nil
        isInitialized = false
        print("[TranscriptionEngine] Model unloaded.")
    }
    
    // MARK: - Private
    
    /// Send a status update to the UI via the callback.
    private func reportStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusUpdate?(message)
        }
    }
}
