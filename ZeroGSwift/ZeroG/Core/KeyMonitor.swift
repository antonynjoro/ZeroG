import Foundation
import Cocoa
import CoreGraphics

// MARK: - Key Codes

private enum KeyCode {
    static let leftControl: CGKeyCode = 59
    static let q: CGKeyCode = 12
}

// MARK: - Key Monitor

/// Monitors global keyboard events using a CGEvent tap.
/// Replaces Python's polling-based `KeyMonitor` with an interrupt-driven approach.
///
/// ## Architecture Difference
/// The Python version polled `CGEventSourceKeyState` every 50ms in a busy loop,
/// consuming 2–5% CPU at idle. This implementation uses `CGEvent.tapCreate()` —
/// an OS-level callback that fires only when a relevant key event occurs.
/// Idle CPU usage: <0.1%.
final class KeyMonitor {
    
    // MARK: Dependencies
    
    private let stateMachine: AppStateMachine
    private let onStartRecording: () -> Void
    private let onStopRecording: (Bool) -> Void  // (useGemini)
    
    // MARK: State
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isControlPressed = false
    private var isQPressedDuringSession = false
    private var recordingStartTime: Date?
    
    /// Safety timeout to prevent stuck recording state (2 minutes).
    private let maxRecordingDuration: TimeInterval = 120.0
    private var timeoutTimer: Timer?
    
    // MARK: Lifecycle
    
    init(
        stateMachine: AppStateMachine,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping (Bool) -> Void
    ) {
        self.stateMachine = stateMachine
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Start / Stop
    
    /// Install a CGEvent tap to monitor modifier key changes globally.
    /// Requires Accessibility permissions (Input Monitoring).
    func start() {
        // Event mask: flagsChanged (modifier keys) + keyDown (to detect Q)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        
        // Store `self` as an Unmanaged pointer to pass into the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                // Handle tap being disabled by the system
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    return Unmanaged.passRetained(event)
                }
                
                if let userInfo = userInfo {
                    let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    monitor.handleEvent(event)
                }
                
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        ) else {
            let processName = ProcessInfo.processInfo.processName
            let parentApp = Bundle.main.bundleIdentifier ?? "this app"
            print("""
            ⚠️ [KeyMonitor] Failed to create event tap!
            
            To fix this, grant Input Monitoring permissions:
              1. Open System Settings → Privacy & Security → Input Monitoring
              2. Click '+' and add the app that launched ZeroG
                 (e.g., Terminal.app, Xcode.app, or iTerm.app)
              3. Also add it under Accessibility
              4. Restart ZeroG
            
            Process: \(processName) | Bundle: \(parentApp)
            """)
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        CGEvent.tapEnable(tap: tap, enable: true)
        
        #if DEBUG
        print("[KeyMonitor] Event tap installed. Monitoring Left Control key.")
        #endif
    }
    
    /// Remove the event tap and clean up.
    func stop() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        
        #if DEBUG
        print("[KeyMonitor] Event tap removed.")
        #endif
    }
    
    // MARK: - Event Handling
    
    /// Process a raw CGEvent from the tap callback.
    private func handleEvent(_ event: CGEvent) {
        let type = event.type
        
        // Handle modifier key changes (Control press/release)
        if type == .flagsChanged {
            let flags = event.flags
            let isCtrlNow = flags.contains(.maskControl)
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // Only respond to Left Control (keycode 59)
            guard keyCode == Int64(KeyCode.leftControl) else { return }
            
            if isCtrlNow && !isControlPressed {
                controlPressed()
            } else if !isCtrlNow && isControlPressed {
                controlReleased()
            }
        }
        
        // Handle keyDown events (detect Q while Control is held)
        if type == .keyDown && isControlPressed {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Int64(KeyCode.q) && !isQPressedDuringSession {
                isQPressedDuringSession = true
                DispatchQueue.main.async { [weak self] in
                    self?.stateMachine.useGemini = true
                }
                
                #if DEBUG
                print("[KeyMonitor] Q pressed during session — Gemini mode activated.")
                #endif
            }
        }
    }
    
    // MARK: - Control Key Actions
    
    private func controlPressed() {
        isControlPressed = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let state = self.stateMachine.currentState
            
            // Block recording if the model isn't loaded yet
            guard state.isReady else {
                print("[KeyMonitor] Ignoring Control press — app not ready (state: \(state))")
                return
            }
            
            switch state {
            case .idle, .success, .error:
                self.isQPressedDuringSession = false
                self.stateMachine.useGemini = false
                self.recordingStartTime = Date()
                self.stateMachine.transition(to: .recording)
                self.onStartRecording()
                self.startTimeoutTimer()
            default:
                break
            }
        }
    }
    
    private func controlReleased() {
        isControlPressed = false
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let state = self.stateMachine.currentState
            
            if state == .recording {
                let useGemini = self.isQPressedDuringSession
                self.stateMachine.transition(to: .processing)
                self.onStopRecording(useGemini)
            }
        }
        
        recordingStartTime = nil
    }
    
    // MARK: - Safety Timeout
    
    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            
            #if DEBUG
            print("[KeyMonitor] Recording timeout (\(self.maxRecordingDuration)s) — forcing stop.")
            #endif
            
            self.isControlPressed = false
            let useGemini = self.isQPressedDuringSession
            self.stateMachine.transition(to: .processing)
            self.onStopRecording(useGemini)
        }
    }
}
