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
    
    // MARK: Text Polish

    /// Legacy UserDefaults key under which a cloud Gemini API key used to be stored.
    /// Cloud Gemini was removed in favour of on-device Apple Foundation Models;
    /// kept only so launch can delete any leftover key (see `Config.load`).
    static let legacyGoogleAPIKeyDefaultsKey = "GOOGLE_API_KEY"

    /// Bundle resource (sans extension) holding the polish system prompt.
    static let polishPromptResource = "polish_prompt"

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

    // MARK: Timing

    /// UI / lifecycle delays, in seconds. Centralized so the perceived-latency knobs
    /// aren't scattered as magic numbers across the codebase.
    enum Timing {
        /// How long to hold the injected text on the clipboard before restoring the
        /// user's original contents. Must outlast the simulated Cmd+V paste.
        static let clipboardRestore: TimeInterval = 0.6

        /// How long the `.success` HUD lingers before auto-returning to `.idle`.
        static let successReset: TimeInterval = 2.0

        /// How long an `.error` HUD lingers before auto-returning to `.idle`.
        static let errorReset: TimeInterval = 3.0

        /// HUD slide-in / slide-out animation durations.
        static let hudSlideIn: TimeInterval = 0.3
        static let hudSlideOut: TimeInterval = 0.25
    }

    // MARK: Notifications

    /// userInfo keys for the notifications this app posts.
    enum NotificationKeys {
        static let triggerKey = "triggerKey"
    }

    // MARK: Trigger Key

    private static let triggerKeyDefaultsKey = "TriggerKeyID"

    static var triggerKey: TriggerKey {
        let id = UserDefaults.standard.string(forKey: triggerKeyDefaultsKey) ?? "leftControl"
        return TriggerKey.from(id: id)
    }

    static func setTriggerKey(_ key: TriggerKey) {
        UserDefaults.standard.set(key.id, forKey: triggerKeyDefaultsKey)
        NotificationCenter.default.post(name: .triggerKeyDidChange, object: nil, userInfo: [NotificationKeys.triggerKey: key])
    }

    // MARK: Polish Shortcut

    /// Modifier subset for the global Polish shortcut. Kept Foundation-only (no
    /// AppKit) so Config stays portable; KeyMonitor maps it to CGEventFlags.
    struct PolishModifiers: OptionSet, Equatable {
        let rawValue: Int
        static let control = PolishModifiers(rawValue: 1 << 0)
        static let option  = PolishModifiers(rawValue: 1 << 1)
        static let shift   = PolishModifiers(rawValue: 1 << 2)
        static let command = PolishModifiers(rawValue: 1 << 3)

        var glyphs: String {
            var s = ""
            if contains(.control) { s += "⌃" }
            if contains(.option)  { s += "⌥" }
            if contains(.shift)   { s += "⇧" }
            if contains(.command) { s += "⌘" }
            return s
        }
    }

    /// A global keyboard shortcut that polishes the last transcription and pastes
    /// the result. `keyCode` is a virtual key code; `modifiers` must match exactly.
    struct PolishShortcut: Equatable {
        let keyCode: Int
        let modifiers: PolishModifiers

        var displayString: String { modifiers.glyphs + Self.keyName(keyCode) }

        static func keyName(_ code: Int) -> String {
            switch code {
            case 49: return "Space"
            case 35: return "P"
            case 36: return "Return"
            default: return "Key \(code)"
            }
        }
    }

    /// Default Polish shortcut: ⌃⌥P (avoids common system chords).
    static let defaultPolishShortcut = PolishShortcut(keyCode: 35, modifiers: [.control, .option])

    /// Selectable presets for the menu (configurable from day one without a
    /// fragile live key-recorder).
    static let polishShortcutPresets: [PolishShortcut] = [
        PolishShortcut(keyCode: 35, modifiers: [.control, .option]),   // ⌃⌥P
        PolishShortcut(keyCode: 49, modifiers: [.control, .option]),   // ⌃⌥Space
        PolishShortcut(keyCode: 35, modifiers: [.control, .command]),  // ⌃⌘P
        PolishShortcut(keyCode: 35, modifiers: [.option, .command]),   // ⌥⌘P
    ]

    private static let polishShortcutKeyCodeKey = "PolishShortcutKeyCode"
    private static let polishShortcutModsKey = "PolishShortcutModifiers"

    static var polishShortcut: PolishShortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: polishShortcutKeyCodeKey) != nil else { return defaultPolishShortcut }
        return PolishShortcut(
            keyCode: d.integer(forKey: polishShortcutKeyCodeKey),
            modifiers: PolishModifiers(rawValue: d.integer(forKey: polishShortcutModsKey)))
    }

    static func setPolishShortcut(_ shortcut: PolishShortcut) {
        let d = UserDefaults.standard
        d.set(shortcut.keyCode, forKey: polishShortcutKeyCodeKey)
        d.set(shortcut.modifiers.rawValue, forKey: polishShortcutModsKey)
    }

    // MARK: Whisper Model

    /// The WhisperKit model variant to use.
    static let whisperModel: String = "large-v3-v20240930_turbo"

    // MARK: STT Backend (FluidAudio/Parakeet spike)

    /// Selectable speech-to-text backend. Spike-only knob (`spike/fluidaudio-parakeet`):
    /// lets us A/B WhisperKit against FluidAudio's Parakeet on the same audio.
    /// See docs/spikes/fluidaudio-parakeet-spike.md.
    enum STTBackend: String {
        case whisper
        case parakeetV2
        case parakeetV3
    }

    /// UserDefaults / environment key for the selected STT backend.
    private static let sttBackendDefaultsKey = "STTBackend"

    /// The active STT backend. UserDefaults wins over the environment; falls back to
    /// `.parakeetV3` — the chosen engine (decision 2026-06-07). Whisper remains selectable
    /// only until the Whisper engine is removed; see docs/spikes/fluidaudio-parakeet-spike.md.
    static var sttBackend: STTBackend {
        let raw = UserDefaults.standard.string(forKey: sttBackendDefaultsKey)
            ?? ProcessInfo.processInfo.environment[sttBackendDefaultsKey]
        return raw.flatMap(STTBackend.init(rawValue:)) ?? .parakeetV3
    }

    /// Persist the selected STT backend (used by the spike's menu-bar toggle).
    static func setSTTBackend(_ backend: STTBackend) {
        UserDefaults.standard.set(backend.rawValue, forKey: sttBackendDefaultsKey)
    }

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

    /// Posted when an action could not complete because a permission is missing
    /// (e.g. paste blocked by missing Accessibility). Observed by the app to open
    /// the setup wizard. Shared constant — never a raw string at call sites.
    static let permissionsNeeded = Notification.Name("ZeroG.permissionsNeeded")
}

extension Config {
    // MARK: Load
    
    /// Load configuration from `.env` file if present (development convenience).
    static func load() {
        loadDotEnv()
        // One-time cleanup: cloud Gemini is gone, so purge any API key a previous
        // version left in UserDefaults (it was the one piece of cloud config).
        UserDefaults.standard.removeObject(forKey: legacyGoogleAPIKeyDefaultsKey)
    }
    
    // MARK: - Private
    
    /// Simple `.env` file parser for development convenience.
    private static func loadDotEnv() {
        let envPath = Bundle.main.bundlePath
            .components(separatedBy: "/")
            .dropLast(1) // Remove .app bundle
            .joined(separator: "/")
            + "/.env"

        // Reading anything under a macOS-protected user folder (Documents/Desktop/
        // Downloads) triggers a TCC "would like to access files…" prompt that has
        // nothing to do with ZeroG's real permissions. Dev builds often live under
        // ~/Documents, so skip the .env probe there — a shipped /Applications copy
        // is unaffected, and keys still come from UserDefaults / env vars.
        if isUnderProtectedDirectory(envPath) {
            Log.debug("Config", "Skipping .env under a protected folder (avoids a TCC prompt): \(envPath)")
            return
        }

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
        
        Log.debug("Config", "Loaded .env file from: \(envPath)")
    }

    /// Whether `path` sits inside a macOS-protected user folder, where a read
    /// would provoke a TCC permission prompt. Uses only path lookups (no file
    /// access), so calling it never triggers the prompt itself.
    private static func isUnderProtectedDirectory(_ path: String) -> Bool {
        let fm = FileManager.default
        let protectedRoots: [String] = [.documentDirectory, .desktopDirectory, .downloadsDirectory]
            .compactMap { fm.urls(for: $0, in: .userDomainMask).first?.path }
        return protectedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
