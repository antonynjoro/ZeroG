import Foundation
import Combine

// MARK: - Application State

/// Represents the discrete states of the ZeroG application lifecycle.
enum AppState: Equatable {
    case loading(String)   // Model downloading / initializing, with status message
    case idle
    case recording
    case processing
    /// Running the on-device polish on the last transcription (post-hoc action).
    case polishing
    case success
    case error(String)
    /// Paste was blocked by a missing permission; the transcript was copied to
    /// the clipboard instead. LINGERING: never auto-reset — the HUD stays until
    /// the user acts (clicks it, or starts the next recording).
    case needsPermission(String)

    /// Whether the app is ready to accept recording commands.
    /// `.needsPermission` is ready on purpose: the next hotkey press must start a
    /// fresh recording (clearing the lingering HUD), not be swallowed.
    var isReady: Bool {
        switch self {
        case .idle, .success, .error, .needsPermission: return true
        default: return false
        }
    }

    /// Human-readable status text for the menu bar.
    var statusText: String {
        switch self {
        case .loading(let msg): return msg
        case .idle: return "Ready — Hold \(Config.triggerKey.displayName) to record"
        case .recording: return "Recording..."
        case .processing: return "Transcribing..."
        case .polishing: return "Polishing..."
        case .success: return "Done ✓"
        case .error(let msg): return "Error: \(msg)"
        case .needsPermission(let msg): return "Copied to clipboard — \(msg)"
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

    /// The most recent transcription result, available for manual clipboard copy
    /// and the on-device polish action.
    @Published var lastTranscription: String?

    // MARK: State Transitions
    
    func transition(to newState: AppState) {
        guard newState != currentState else { return }
        
        let previous = currentState
        currentState = newState

        Log.debug("StateMachine", "\(previous) → \(newState)")
    }
    
    /// Convenience: transition to `.idle` after a delay.
    func resetToIdle(after delay: TimeInterval = Config.Timing.successReset) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.transition(to: .idle)
        }
    }
}
