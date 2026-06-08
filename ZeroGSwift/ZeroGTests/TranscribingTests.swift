import Foundation
import Testing
@testable import ZeroG

/// A no-op `Transcribing` for testing the engine-agnostic seam without loading any model.
/// Records calls so tests can assert the call site routes through the protocol.
final class MockTranscriber: Transcribing {
    var onStatusUpdate: ((String) -> Void)?
    private(set) var initializeCalled = false
    private(set) var lastAudio: [Float]?
    var cannedResult = "mock transcript"

    func initialize() async throws { initializeCalled = true }

    func transcribe(_ audioArray: [Float]) async throws -> String {
        lastAudio = audioArray
        return cannedResult
    }

    func unloadModel() {}
}

/// Tests for the `Transcribing` seam and the `Config.STTBackend` selection mechanism that
/// the FluidAudio/Parakeet spike depends on. No model loading, no network.
@Suite
struct TranscribingTests {

    // MARK: Engine-agnostic seam

    @Test("AudioRecorder accepts any Transcribing (engine-agnostic call site)")
    func audioRecorderTakesProtocol() {
        let mock = MockTranscriber()
        // Compiles only if AudioRecorder's dependency is the protocol, not a concrete engine.
        _ = AudioRecorder(stateMachine: AppStateMachine(), transcriptionEngine: mock)
    }

    @Test("The concrete WhisperKit engine conforms to Transcribing")
    func whisperConforms() {
        let engine: Transcribing = TranscriptionEngine()
        #expect(engine is TranscriptionEngine)
    }

    @Test("Mock transcribe returns its canned result and captures the audio")
    func mockRoundTrips() async throws {
        let mock = MockTranscriber()
        mock.cannedResult = "hello"
        let out = try await mock.transcribe([0.1, 0.2, 0.3])
        #expect(out == "hello")
        #expect(mock.lastAudio == [0.1, 0.2, 0.3])
    }

    @Test("STTBackend raw values are stable (used as the persisted key)")
    func rawValuesStable() {
        #expect(Config.STTBackend.whisper.rawValue == "whisper")
        #expect(Config.STTBackend.parakeetV2.rawValue == "parakeetV2")
        #expect(Config.STTBackend.parakeetV3.rawValue == "parakeetV3")
    }
}

/// Backend-selection tests mutate the shared `UserDefaults` "STTBackend" key, so they must
/// run one at a time — `.serialized` prevents the parallel test runner from racing them.
@Suite(.serialized)
struct STTBackendSelectionTests {
    private static let key = "STTBackend"

    @Test("sttBackend defaults to .parakeetV3 when no preference is set")
    func defaultsToParakeetV3() {
        let prior = UserDefaults.standard.string(forKey: Self.key)
        defer { UserDefaults.standard.set(prior, forKey: Self.key) }

        UserDefaults.standard.removeObject(forKey: Self.key)
        #expect(Config.sttBackend == .parakeetV3)
    }

    @Test("sttBackend reads a stored Parakeet preference")
    func readsStoredPreference() {
        let prior = UserDefaults.standard.string(forKey: Self.key)
        defer { UserDefaults.standard.set(prior, forKey: Self.key) }

        Config.setSTTBackend(.parakeetV3)
        #expect(Config.sttBackend == .parakeetV3)
    }

    @Test("An unrecognized stored value falls back to .parakeetV3")
    func unrecognizedFallsBack() {
        let prior = UserDefaults.standard.string(forKey: Self.key)
        defer { UserDefaults.standard.set(prior, forKey: Self.key) }

        UserDefaults.standard.set("garbage", forKey: Self.key)
        #expect(Config.sttBackend == .parakeetV3)
    }
}
