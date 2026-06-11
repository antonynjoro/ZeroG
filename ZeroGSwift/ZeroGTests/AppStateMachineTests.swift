import Testing
@testable import ZeroG

// MARK: - AppStateMachine Tests

struct AppStateMachineTests {
    
    @Test("Initial state is loading")
    func initialState() {
        let machine = AppStateMachine()
        if case .loading = machine.currentState {
            // Expected
        } else {
            Issue.record("Expected loading state, got \(machine.currentState)")
        }
        #expect(machine.audioLevel == 0.0)
    }
    
    @Test("isReady returns true for idle, success, error, needsPermission")
    func isReady() {
        let machine = AppStateMachine()

        machine.transition(to: .idle)
        #expect(machine.currentState.isReady == true)

        machine.transition(to: .success)
        #expect(machine.currentState.isReady == true)

        machine.transition(to: .error("test"))
        #expect(machine.currentState.isReady == true)

        // The lingering paste-blocked state must NOT swallow the next hotkey press.
        machine.transition(to: .needsPermission("Grant Accessibility to paste"))
        #expect(machine.currentState.isReady == true)
    }
    
    @Test("isReady returns false during loading, recording, processing")
    func isNotReady() {
        let machine = AppStateMachine()
        
        #expect(machine.currentState.isReady == false) // loading
        
        machine.transition(to: .recording)
        #expect(machine.currentState.isReady == false)
        
        machine.transition(to: .processing)
        #expect(machine.currentState.isReady == false)
    }

    @Test("statusText covers all user-visible states")
    func statusTextForAllStates() {
        let cases: [(AppState, String)] = [
            (.loading("Loading model"), "Loading model"),
            (.idle, "Ready"),
            (.recording, "Recording"),
            (.processing, "Transcribing"),
            (.success, "Done"),
            (.error("Microphone denied"), "Microphone denied"),
            (.needsPermission("Grant Accessibility to paste"), "Copied to clipboard")
        ]

        for (state, expectedText) in cases {
            #expect(state.statusText.contains(expectedText))
        }
    }

    @Test("Session fields can track audio level and transcription")
    func sessionFields() {
        let machine = AppStateMachine()

        machine.audioLevel = 0.42
        machine.lastTranscription = "hello world"

        #expect(machine.audioLevel == 0.42)
        #expect(machine.lastTranscription == "hello world")
    }
    
    @Test("Full lifecycle: loading → idle → recording → processing → success → idle")
    func fullLifecycle() {
        let machine = AppStateMachine()
        
        machine.transition(to: .idle)
        #expect(machine.currentState == .idle)
        
        machine.transition(to: .recording)
        #expect(machine.currentState == .recording)
        
        machine.transition(to: .processing)
        #expect(machine.currentState == .processing)
        
        machine.transition(to: .success)
        #expect(machine.currentState == .success)
        
        machine.transition(to: .idle)
        #expect(machine.currentState == .idle)
    }
    
    @Test("Error state carries message")
    func errorState() {
        let machine = AppStateMachine()
        machine.transition(to: .error("Mic Error"))
        
        if case .error(let message) = machine.currentState {
            #expect(message == "Mic Error")
        } else {
            Issue.record("Expected error state")
        }
    }
    
    @Test("statusText is useful for each state")
    func statusText() {
        let machine = AppStateMachine()
        #expect(machine.currentState.statusText.contains("Starting"))
        
        machine.transition(to: .idle)
        #expect(machine.currentState.statusText.contains("Ready"))
        
        machine.transition(to: .recording)
        #expect(machine.currentState.statusText.contains("Recording"))
        
        machine.transition(to: .error("Test"))
        #expect(machine.currentState.statusText.contains("Test"))
    }

    @Test("resetToIdle transitions back to idle after delay")
    func resetToIdle() async throws {
        let machine = AppStateMachine()
        machine.transition(to: .success)

        machine.resetToIdle(after: 0.01)
        try await Task.sleep(for: .milliseconds(50))

        #expect(machine.currentState == .idle)
    }
}
