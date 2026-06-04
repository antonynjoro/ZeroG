import Foundation
import Testing
@testable import ZeroG

@Suite
struct SilenceTrackerTests {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func makeTracker() -> SilenceTracker {
        SilenceTracker(rmsThreshold: 0.01, silenceDuration: 12.0)
    }

    @Test("Loud input never stops")
    func loudKeepsRecording() {
        var tracker = makeTracker()
        for offset in stride(from: 0.0, through: 30.0, by: 1.0) {
            #expect(tracker.observe(rms: 0.5, at: base.addingTimeInterval(offset)) == .keepRecording)
        }
    }

    @Test("Silence shorter than the duration keeps recording")
    func shortSilenceKeepsRecording() {
        var tracker = makeTracker()
        #expect(tracker.observe(rms: 0.0, at: base) == .keepRecording)              // clock starts
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(11.9)) == .keepRecording)
    }

    @Test("Silence past the duration triggers a stop")
    func longSilenceStops() {
        var tracker = makeTracker()
        #expect(tracker.observe(rms: 0.0, at: base) == .keepRecording)              // clock starts
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(12.1)) == .stop)
    }

    @Test("Stop fires at most once per session")
    func firesOnce() {
        var tracker = makeTracker()
        _ = tracker.observe(rms: 0.0, at: base)
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(13.0)) == .stop)
        // Still silent, but it already fired — don't fire again.
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(30.0)) == .keepRecording)
    }

    @Test("A sound above the floor resets the silence clock")
    func voiceResetsClock() {
        var tracker = makeTracker()
        _ = tracker.observe(rms: 0.0, at: base)                                     // clock starts at t=0
        _ = tracker.observe(rms: 0.5, at: base.addingTimeInterval(11.0))            // voice resets
        // 11s of fresh silence from t=11 is not yet 12s — should keep recording.
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(22.0)) == .keepRecording)
        // ...but crossing 12s from the reset point does stop.
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(34.1)) == .stop)
    }

    @Test("reset re-arms the tracker after a stop")
    func resetReArms() {
        var tracker = makeTracker()
        _ = tracker.observe(rms: 0.0, at: base)
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(13.0)) == .stop)

        tracker.reset()
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(40.0)) == .keepRecording) // clock restarts
        #expect(tracker.observe(rms: 0.0, at: base.addingTimeInterval(52.1)) == .stop)
    }
}
