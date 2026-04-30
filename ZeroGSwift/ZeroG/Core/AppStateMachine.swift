import Foundation
import Combine

// MARK: - Application State

/// Represents the discrete states of the ZeroG application lifecycle.
enum AppState: Equatable {
    case loading(String)   // Model downloading / initializing, with status message
    case idle
    case recording
    case processing
    case success
    case error(String)
    
    /// Whether the app is ready to accept recording commands.
    var isReady: Bool {
        switch self {
        case .idle, .success, .error: return true
        default: return false
        }
    }
    
    /// Human-readable status text for the menu bar.
    var statusText: String {
        switch self {
        case .loading(let msg): return msg
        case .idle: return "Ready — Hold Control to record"
        case .recording: return "Recording..."
        case .processing: return "Transcribing..."
        case .success: return "Done ✓"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - State Machine

/// Centralized state machine using Combine for reactive UI updates.
final class AppStateMachine: ObservableObject {
    
    // MARK: Published State
    
    @Published private(set) var currentState: AppState = .loading("Starting up...")
    
    /// Real-time audio input level (0.0–1.0) for HUD waveform visualization.
    @Published var audioLevel: Float = 0.0

    /// The most recent transcription result, available for manual clipboard copy.
    @Published var lastTranscription: String?

    // MARK: Session Context
    
    /// Whether the current recording session should use Gemini post-processing.
    @Published var useGemini: Bool = false
    
    // MARK: State Transitions
    
    func transition(to newState: AppState) {
        guard newState != currentState else { return }
        
        let previous = currentState
        currentState = newState
        
        print("[StateMachine] \(previous) → \(newState)")
    }
    
    /// Convenience: transition to `.idle` after a delay.
    func resetToIdle(after delay: TimeInterval = 2.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.transition(to: .idle)
        }
    }
}
