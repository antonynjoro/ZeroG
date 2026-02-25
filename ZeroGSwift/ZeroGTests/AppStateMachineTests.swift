import Testing
@testable import ZeroG

// MARK: - AppStateMachine Tests

/// Tests for the Combine-based state machine.
/// Validates state transitions, reset behavior, and published property updates.
struct AppStateMachineTests {
    
    @Test("Initial state is idle")
    @MainActor
    func initialState() {
        let machine = AppStateMachine()
        #expect(machine.currentState == .idle)
        #expect(machine.audioLevel == 0.0)
        #expect(machine.useGemini == false)
    }
    
    @Test("Transition from idle to recording")
    @MainActor
    func transitionToRecording() {
        let machine = AppStateMachine()
        machine.transition(to: .recording)
        #expect(machine.currentState == .recording)
    }
    
    @Test("Full lifecycle: idle → recording → processing → success → idle")
    @MainActor
    func fullLifecycle() {
        let machine = AppStateMachine()
        
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
    @MainActor
    func errorState() {
        let machine = AppStateMachine()
        machine.transition(to: .error("Mic Error"))
        
        if case .error(let message) = machine.currentState {
            #expect(message == "Mic Error")
        } else {
            Issue.record("Expected error state")
        }
    }
    
    @Test("Duplicate transition is ignored")
    @MainActor
    func duplicateTransition() {
        let machine = AppStateMachine()
        machine.transition(to: .recording)
        machine.transition(to: .recording) // Should not panic or change
        #expect(machine.currentState == .recording)
    }
    
    @Test("Audio level updates independently of state")
    @MainActor
    func audioLevel() {
        let machine = AppStateMachine()
        machine.audioLevel = 0.75
        #expect(machine.audioLevel == 0.75)
    }
    
    @Test("useGemini flag resets independently")
    @MainActor
    func geminiFlag() {
        let machine = AppStateMachine()
        machine.useGemini = true
        #expect(machine.useGemini == true)
        machine.useGemini = false
        #expect(machine.useGemini == false)
    }
}
