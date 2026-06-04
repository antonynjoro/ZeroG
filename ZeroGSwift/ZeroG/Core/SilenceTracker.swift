import Foundation

// MARK: - Silence Tracker

/// Pure decision logic for the safety-only auto-stop: if the input stays below
/// the RMS threshold for longer than `silenceDuration`, recording should end.
///
/// Extracted from `AudioRecorder.processAudioBuffer` so the thresholds and timing
/// can be unit-tested without an `AVAudioEngine`. Holds no audio — it's fed an
/// RMS value and a timestamp per buffer and returns a decision. Fires at most
/// once per recording session; `reset()` re-arms it for the next session.
struct SilenceTracker {
    let rmsThreshold: Float
    let silenceDuration: TimeInterval

    private var silenceStart: Date?
    private var hasFired = false

    enum Decision: Equatable {
        case keepRecording
        case stop
    }

    init(rmsThreshold: Float, silenceDuration: TimeInterval) {
        self.rmsThreshold = rmsThreshold
        self.silenceDuration = silenceDuration
    }

    /// Feed one buffer's RMS level and the time it was observed.
    mutating func observe(rms: Float, at now: Date) -> Decision {
        // Any sound above the floor resets the silence clock.
        guard rms < rmsThreshold else {
            silenceStart = nil
            return .keepRecording
        }

        // Already auto-stopped this session — stay quiet until reset.
        guard !hasFired else { return .keepRecording }

        guard let start = silenceStart else {
            silenceStart = now
            return .keepRecording
        }

        if now.timeIntervalSince(start) > silenceDuration {
            hasFired = true
            return .stop
        }
        return .keepRecording
    }

    /// Re-arm for a new recording session.
    mutating func reset() {
        silenceStart = nil
        hasFired = false
    }
}
