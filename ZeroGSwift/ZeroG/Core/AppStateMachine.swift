import Foundation
import Combine

// MARK: - Application State

/// Represents the discrete states of the ZeroG application lifecycle.
enum AppState: Equatable {
    case idle
    case recording
    case processing
    case success
    case error(String)
}

// MARK: - State Machine

/// Centralized, thread-safe state machine using Combine for reactive UI updates.
/// Replaces the Python StateMachine singleton + manual Observer pattern.
///
/// SwiftUI views and controllers observe `@Published` properties directly —
/// no manual observer registration needed.
@MainActor
final class AppStateMachine: ObservableObject {
    
    // MARK: Published State
    
    /// Current application state. UI components observe this via `@ObservedObject`.
    @Published private(set) var currentState: AppState = .idle
    
    /// Real-time audio input level (0.0–1.0) for HUD waveform visualization.
    @Published var audioLevel: Float = 0.0
    
    // MARK: Session Context
    
    /// Whether the current recording session should use Gemini post-processing.
    @Published var useGemini: Bool = false
    
    // MARK: State Transitions
    
    /// Transition to a new state. Logs the transition for debugging.
    func transition(to newState: AppState) {
        guard newState != currentState else { return }
        
        let previous = currentState
        currentState = newState
        
        #if DEBUG
        print("[StateMachine] \(previous) → \(newState)")
        #endif
    }
    
    /// Convenience: transition to `.idle` after a delay (e.g., after success/error display).
    func resetToIdle(after delay: TimeInterval = 2.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            transition(to: .idle)
        }
    }
}
