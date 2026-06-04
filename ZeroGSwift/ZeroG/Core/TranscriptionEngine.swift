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

    /// Decoding options tuned for low latency: English-only, no language detection probe.
    /// Chunking is disabled (.none) — VAD chunking only ever activated above one 30s
    /// window and gave long recordings isolated chunks prone to boundary truncation and
    /// tail hallucination. Trailing-silence hallucinations are handled post-decode in
    /// `cleanTranscript`, not by audio-side gating.
    // internal so tests can assert these values don't regress
    static let fastDecodingOptions = DecodingOptions(
        task: .transcribe,
        language: "en",
        temperature: 0.0,
        temperatureFallbackCount: 1,
        detectLanguage: false,
        skipSpecialTokens: true,
        withoutTimestamps: false,
        suppressBlank: true,
        compressionRatioThreshold: 2.4,
        logProbThreshold: -1.0,
        noSpeechThreshold: 0.6,
        chunkingStrategy: ChunkingStrategy.none
    )
    
    /// Callback for status updates during initialization (download progress, model loading phases).
    var onStatusUpdate: ((String) -> Void)?
    
    // MARK: Initialization
    
    init(modelName: String? = nil) {
        self.modelName = modelName ?? Config.whisperModel
    }
    
    /// Load the WhisperKit model with progress reporting.
    func initialize() async throws {
        guard !isInitialized else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        Log.debug("TranscriptionEngine", "Attempting model load: \(modelName)")

        do {
            reportStatus("Downloading model: \(modelName)...")
            
            // Step 1: Download the model with progress reporting
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                progressCallback: { [weak self] progress in
                    let pct = Int(progress.fractionCompleted * 100)
                    let message = "Downloading model: \(pct)%"
                    self?.reportStatus(message)
                    Log.debug("TranscriptionEngine", message)
                }
            )
            
            reportStatus("Loading model into memory...")
            Log.debug("TranscriptionEngine", "Download complete. Loading from: \(modelFolder.path)")
            
            // Step 2: Initialize WhisperKit with the downloaded model folder
            #if DEBUG
            let verboseLogging = true
            #else
            let verboseLogging = false
            #endif

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                ),
                verbose: verboseLogging,
                prewarm: true,
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
                Log.debug("TranscriptionEngine", "Model state: \(String(describing: oldState)) → \(String(describing: newState))")
            }
            
            // Step 3: Load models into memory
            reportStatus("Compiling for Neural Engine...")
            try await kit.loadModels()

            // Step 4: Force CoreML decoder specialization now so the user's first
            // dictation doesn't pay the ~300–600 ms cold-start cost.
            reportStatus("Priming decoder...")
            let warmupAudio = [Float](repeating: 0.0, count: Int(AudioConstants.sampleRate)) // 1 s of silence
            _ = try? await kit.transcribe(audioArray: warmupAudio, decodeOptions: Self.fastDecodingOptions)

            whisperKit = kit
            isInitialized = true
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            Log.debug("TranscriptionEngine", "✅ Model '\(modelName)' loaded in \(String(format: "%.1f", duration))s")
            reportStatus("Ready!")

        } catch {
            Log.error("TranscriptionEngine", "❌ Model '\(modelName)' failed: \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
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
        
        let results = try await kit.transcribe(audioArray: audioArray, decodeOptions: Self.fastDecodingOptions)

        // Flatten WhisperKit segments into our decoupled adapter type, preserving the
        // per-segment confidence the cleanup pass needs (and the base API discards).
        let segments = results.flatMap { $0.segments }.map {
            DecodedSegment(text: $0.text, noSpeechProb: $0.noSpeechProb, avgLogprob: $0.avgLogprob)
        }

        return Self.cleanTranscript(segments)
    }

    // MARK: - Transcript cleanup

    /// Decoupled view of a WhisperKit segment carrying only what the cleanup pass needs.
    /// Keeps `cleanTranscript` testable without constructing full `TranscriptionSegment`s.
    struct DecodedSegment {
        let text: String
        let noSpeechProb: Float
        let avgLogprob: Float
    }

    /// Strip trailing-silence hallucinations ("thank you thank you…") from a decoded
    /// transcript without touching real speech. Operates in the text domain so audio can
    /// stay generous (no word clipping). Order matters:
    ///   a. Drop trailing segments the model itself flags as silence (high noSpeechProb).
    ///   b. Backstop: drop a standalone final segment that's exactly a known caption-ism.
    ///   c. Collapse pathological repeated phrase-runs ("thank you thank you thank you").
    ///   d. Final backstop: if the whole thing collapsed down to a lone caption-ism, drop it.
    /// internal so tests can drive it directly.
    static func cleanTranscript(_ segments: [DecodedSegment]) -> String {
        let drop = Config.TranscriptionQuality.trailingNoSpeechDrop

        // a. Drop silence-origin trailing segments (primary signal). Walk from the end and
        //    stop at the first segment that looks like real speech.
        var kept = segments
        while let last = kept.last,
              !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              last.noSpeechProb >= drop {
            Log.debug("TranscriptionEngine", "Dropped trailing hallucination (noSpeechProb=\(String(format: "%.2f", last.noSpeechProb)), avgLogprob=\(String(format: "%.2f", last.avgLogprob))): \"\(last.text)\"")
            kept.removeLast()
        }

        // b. Backstop: a surviving standalone final segment that's exactly a caption-ism.
        if let last = kept.last, isTrailingHallucination(last.text) {
            Log.debug("TranscriptionEngine", "Dropped trailing caption-ism (backstop): \"\(last.text)\"")
            kept.removeLast()
        }

        // c. Collapse repeated phrase-runs on the joined text, then normalize whitespace.
        let joined = kept.map { $0.text }.joined(separator: " ")
        let text = collapseRepetitions(joined)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // d. After collapsing, a repeated run like "thank you thank you thank you" reduces
        //    to a single caption-ism — drop it if that's all that's left.
        if isTrailingHallucination(text) {
            Log.debug("TranscriptionEngine", "Dropped collapsed caption-ism: \"\(text)\"")
            return ""
        }
        return text
    }

    /// True if `text`, normalized (lowercased, surrounding whitespace and trailing
    /// punctuation stripped), exactly matches a known caption-ism. Exact-match only —
    /// never substring — so "thank you for the report" is untouched.
    private static func isTrailingHallucination(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
            .trimmingCharacters(in: .whitespaces)
        return Config.TranscriptionQuality.trailingHallucinations.contains(normalized)
    }

    /// Collapse any run where a short phrase (1–3 words) repeats 3+ times consecutively
    /// down to a single instance. Targets "thank you thank you thank you"; real speech
    /// rarely repeats a phrase 3×+ back-to-back. Case/punctuation-insensitive on the match.
    static func collapseRepetitions(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return text }

        func norm(_ s: String) -> String {
            s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        }

        var result: [String] = []
        var i = 0
        while i < words.count {
            var collapsed = false
            // Try longer phrases first so "very good very good very good" collapses as a
            // 2-word unit rather than mis-collapsing on single "very".
            for phraseLen in stride(from: 3, through: 1, by: -1) {
                guard i + phraseLen <= words.count else { continue }
                let phrase = Array(words[i..<i + phraseLen]).map(norm)
                var reps = 1
                var j = i + phraseLen
                while j + phraseLen <= words.count,
                      Array(words[j..<j + phraseLen]).map(norm) == phrase {
                    reps += 1
                    j += phraseLen
                }
                if reps >= 3 {
                    // Keep one instance (original casing/punctuation), skip the rest.
                    result.append(contentsOf: words[i..<i + phraseLen])
                    i = j
                    collapsed = true
                    break
                }
            }
            if !collapsed {
                result.append(words[i])
                i += 1
            }
        }
        return result.joined(separator: " ")
    }
    
    /// Unload the model to free memory.
    func unloadModel() {
        whisperKit = nil
        isInitialized = false
        Log.debug("TranscriptionEngine", "Model unloaded.")
    }
    
    // MARK: - Private
    
    /// Send a status update to the UI via the callback.
    private func reportStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusUpdate?(message)
        }
    }
}
