import Foundation
import Cocoa
import CoreGraphics

// MARK: - Key Codes

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
    /// Requests that recording end and processing begin.
    private let onStopRecording: () -> Void

    // MARK: State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Whether the tap is currently installed. Guards against a double `start()`
    /// (e.g. the post-grant retry) leaking a second tap + a duplicate
    /// trigger-key observer.
    private(set) var isRunning = false
    /// Throttles the tap-creation failure log to once per failing streak, so
    /// repeated retries while Accessibility is missing don't flood the log.
    private var didLogTapFailure = false
    private var triggerKey: TriggerKey = Config.triggerKey
    private var isTriggerKeyPressed = false
    private var recordingStartTime: Date?

    /// Safety timeout to prevent stuck recording state (2 minutes).
    private let maxRecordingDuration: TimeInterval = 120.0
    private var timeoutTimer: Timer?

    // MARK: Lifecycle

    init(
        stateMachine: AppStateMachine,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void
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
    /// Requires Accessibility trust (a trusted process may create listen-only
    /// taps). Returns whether the tap was created — note tapCreate can succeed
    /// while events are withheld pending trust, so success is NOT a permission
    /// check; gate on AXIsProcessTrusted instead. Idempotent: a second call while
    /// already running is a no-op that reports the existing success.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        // Event mask: flagsChanged (modifier keys) + keyDown (to detect Q)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        // Store `self` as an Unmanaged pointer to pass into the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Re-enable the tap if the system disabled it
                    if let userInfo = userInfo {
                        let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                        if let tap = monitor.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                            Log.debug("KeyMonitor", "Event tap re-enabled after system timeout")
                        }
                    }
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
            guard !didLogTapFailure else { return false }
            didLogTapFailure = true
            let processName = ProcessInfo.processInfo.processName
            let parentApp = Bundle.main.bundleIdentifier ?? "this app"
            Log.error("KeyMonitor", """
            ⚠️ Failed to create event tap!

            To fix this, grant Accessibility permission:
              1. Open System Settings → Privacy & Security → Accessibility
              2. Turn on the toggle for ZeroG (or the app that launched it,
                 e.g. Terminal.app or Xcode.app when running unbundled)
              3. Restart ZeroG

            Process: \(processName) | Bundle: \(parentApp)
            """)
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(triggerKeyChanged(_:)),
            name: .triggerKeyDidChange,
            object: nil
        )

        isRunning = true
        didLogTapFailure = false
        Log.debug("KeyMonitor", "Event tap installed. Monitoring \(triggerKey.displayName) key.")
        return true
    }

    /// Remove the event tap and clean up.
    func stop() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        NotificationCenter.default.removeObserver(self)

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false

        Log.debug("KeyMonitor", "Event tap removed.")
    }

    // MARK: - Trigger Key Change

    @objc private func triggerKeyChanged(_ notification: Notification) {
        guard let newKey = notification.userInfo?[Config.NotificationKeys.triggerKey] as? TriggerKey else { return }

        let wasRecording = isTriggerKeyPressed
        triggerKey = newKey

        if wasRecording {
            isTriggerKeyPressed = false
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            DispatchQueue.main.async { [weak self] in
                self?.onStopRecording()
            }
        }

        Log.debug("KeyMonitor", "Trigger key changed to \(newKey.displayName)")
    }

    // MARK: - Event Handling

    /// Process a raw CGEvent from the tap callback.
    private func handleEvent(_ event: CGEvent) {
        let type = event.type

        // Handle modifier key changes (trigger key press/release)
        if type == .flagsChanged {
            let flags = event.flags
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            guard keyCode == Int64(triggerKey.keyCode) else { return }

            let isTriggerFlagSet = flags.rawValue & triggerKey.deviceFlagMask != 0

            if isTriggerFlagSet && !isTriggerKeyPressed {
                triggerPressed()
            } else if !isTriggerFlagSet && isTriggerKeyPressed {
                triggerReleased()
            }
        }
    }

    // MARK: - Trigger Key Actions

    private func triggerPressed() {
        isTriggerKeyPressed = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let state = self.stateMachine.currentState

            guard state.isReady else {
                Log.debug("KeyMonitor", "Ignoring \(self.triggerKey.displayName) press — app not ready (state: \(state))")
                return
            }

            switch state {
            case .idle, .success, .error, .needsPermission:
                self.recordingStartTime = Date()
                self.stateMachine.transition(to: .recording)
                self.onStartRecording()
                self.startTimeoutTimer()
            default:
                break
            }
        }
    }

    private func triggerReleased() {
        isTriggerKeyPressed = false
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        DispatchQueue.main.async { [weak self] in
            self?.onStopRecording()
        }

        recordingStartTime = nil
    }

    // MARK: - Safety Timeout

    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            guard let self else { return }

            Log.debug("KeyMonitor", "Recording timeout (\(self.maxRecordingDuration)s) — forcing stop.")

            self.isTriggerKeyPressed = false
            self.onStopRecording()
        }
    }
}
