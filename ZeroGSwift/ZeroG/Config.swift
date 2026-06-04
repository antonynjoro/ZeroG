import Foundation

// MARK: - Configuration

/// Application configuration management.
/// Replaces Python's `.env` + `dotenv` with native Swift mechanisms.
///
/// ## Configuration Sources (priority order)
/// 1. Environment variables (for development)
/// 2. UserDefaults (for user preferences)
/// 3. Defaults (hardcoded fallbacks)
enum Config {
    
    // MARK: Debug
    
    /// Whether debug logging is enabled.
    static var isDebugEnabled: Bool {
        ProcessInfo.processInfo.environment["DEBUG"]?.lowercased() == "true"
            || UserDefaults.standard.bool(forKey: "DEBUG")
    }
    
    // MARK: Gemini API
    
    /// Google API key for Gemini integration.
    static var googleAPIKey: String? {
        ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "GOOGLE_API_KEY")
    }
    
    // MARK: Audio

    /// Safety-only silence threshold (RMS amplitude below which is considered true silence).
    /// Interacts with the trailing-audio knobs — see `TranscriptionQuality`.
    static let silenceThreshold: Float = 0.003

    /// Seconds of continuous true silence before auto-stop.
    /// Interacts with the trailing-audio knobs — see `TranscriptionQuality`.
    static let silenceDuration: TimeInterval = 12.0

    /// Seconds to keep recording after key release to capture trailing speech.
    /// Sourced from `TranscriptionQuality.recordingTailSeconds`.
    static let recordingTailDuration: TimeInterval = TranscriptionQuality.recordingTailSeconds

    // MARK: Trigger Key

    private static let triggerKeyDefaultsKey = "TriggerKeyID"

    static var triggerKey: TriggerKey {
        let id = UserDefaults.standard.string(forKey: triggerKeyDefaultsKey) ?? "leftControl"
        return TriggerKey.from(id: id)
    }

    static func setTriggerKey(_ key: TriggerKey) {
        UserDefaults.standard.set(key.id, forKey: triggerKeyDefaultsKey)
        NotificationCenter.default.post(name: .triggerKeyDidChange, object: nil, userInfo: ["triggerKey": key])
    }

    // MARK: Whisper Model

    /// The WhisperKit model variant to use.
    static let whisperModel: String = "large-v3-v20240930_turbo"

    // MARK: Transcription Quality

    /// All transcription quality / anti-hallucination tuning in one place.
    /// These knobs interact — change them together here, not scattered across
    /// AudioRecorder and TranscriptionEngine (which is what caused past flip-flops).
    enum TranscriptionQuality {
        /// A trailing segment whose WhisperKit `noSpeechProb` exceeds this is
        /// treated as a silence hallucination and dropped. Real spoken endings
        /// sit well below; tail caption-isms ("thank you") sit well above.
        static let trailingNoSpeechDrop: Float = 0.5

        /// Caption-isms WhisperKit emits on silence. Secondary backstop only —
        /// matched exact-after-normalization (lowercased, trailing punctuation
        /// stripped) against the final segment, never substring-matched.
        static let trailingHallucinations: Set<String> = [
            "thank you", "thanks for watching", "please subscribe", "you", "bye"
        ]

        /// Of the captured audio, how much trailing silence to keep so the
        /// decoder cleanly finalizes the last word. No latency cost (array slice).
        static let trailingTailSeconds: Double = 0.3

        /// Dead time the app keeps recording after key release before
        /// transcribing. User-perceived latency — keep as low as last-word
        /// capture allows. Lower = snappier but risks clipping a quiet final word.
        static let recordingTailSeconds: Double = 0.3
    }

}

extension Notification.Name {
    static let triggerKeyDidChange = Notification.Name("ZeroG.triggerKeyDidChange")
}

extension Config {
    // MARK: Load
    
    /// Load configuration from `.env` file if present (development convenience).
    static func load() {
        loadDotEnv()
    }
    
    // MARK: - Private
    
    /// Simple `.env` file parser for development convenience.
    private static func loadDotEnv() {
        let envPath = Bundle.main.bundlePath
            .components(separatedBy: "/")
            .dropLast(1) // Remove .app bundle
            .joined(separator: "/")
            + "/.env"
        
        guard FileManager.default.fileExists(atPath: envPath),
              let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return
        }
        
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            
            setenv(key, value, 1)
        }
        
        #if DEBUG
        print("[Config] Loaded .env file from: \(envPath)")
        #endif
    }
}
