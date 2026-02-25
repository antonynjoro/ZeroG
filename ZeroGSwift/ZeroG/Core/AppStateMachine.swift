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
///
/// Note: Not marked `@MainActor` on the class to avoid initialization issues.
/// The `@Published` properties automatically emit on the thread they're set on,
/// and Combine's `.receive(on: DispatchQueue.main)` handles UI thread dispatch.
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
    /// Must be called on the main thread.
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
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.transition(to: .idle)
        }
    }
}
