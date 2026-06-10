import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import Combine

// MARK: - Permission model

/// One of the two macOS permissions ZeroG cannot function without.
/// `allCases` order is also the wizard order ("Permission 1 of 2" …).
///
/// Note: ZeroG does NOT need a separate Input Monitoring grant. Its key listener
/// is a listen-only `CGEvent` tap, which an Accessibility-trusted process is
/// already allowed to create — so Accessibility covers both the trigger-key
/// detection and the paste injection.
enum PermissionKind: CaseIterable {
    case microphone
    case accessibility

    /// User-facing name, matching the System Settings pane label.
    var displayName: String {
        switch self {
        case .microphone:    return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    /// One-line "why we need this" copy.
    var explanation: String {
        switch self {
        case .microphone:    return "So ZeroG can hear your voice while you hold the key."
        case .accessibility: return "So ZeroG can detect your trigger key and type the transcribed text into any app."
        }
    }

    /// HUDIcons PNG (sans extension) for this step's halo.
    var iconName: String {
        switch self {
        case .microphone:    return "onboard-mic"
        case .accessibility: return "onboard-paste"
        }
    }

    /// Deep link to the relevant Privacy & Security pane.
    ///
    /// Centralized here on purpose: macOS Tahoe (26) changed these pane IDs and
    /// broke the equivalent links in other apps until patched. A future fix is
    /// one line each, right here — never inline these strings at call sites.
    var settingsURL: URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        switch self {
        case .microphone:    return URL(string: base + "Privacy_Microphone")
        case .accessibility: return URL(string: base + "Privacy_Accessibility")
        }
    }
}

/// Tri-state authorization. Only `.microphone` ever reports `.notDetermined`;
/// the AX check exposes only granted-or-not, so its `false` maps to `.denied`.
enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

// MARK: - Checking seam

/// Test seam over the raw system permission APIs. `SystemPermissionChecker` is
/// the *only* type that touches AVCaptureDevice / CoreGraphics / Accessibility,
/// so tests can drive `PermissionsManager` with a fake.
protocol PermissionChecking {
    /// Non-prompting status query. Safe to call on a 1s poll.
    func status(for kind: PermissionKind) -> PermissionStatus
    /// Prompting request — call ONCE on a user's button tap, never on a timer.
    /// Completion is delivered on the main thread.
    func request(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void)
}

/// The real implementation, talking to the OS.
///
/// Check vs request are deliberately different calls per kind (see the spike plan):
/// the check variants never prompt; the request variants prompt exactly once.
final class SystemPermissionChecker: PermissionChecking {

    func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:     return .granted
            case .notDetermined:  return .notDetermined
            default:              return .denied   // .denied, .restricted
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        }
    }

    func request(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void) {
        switch kind {
        case .microphone:
            // Only presents a dialog when status is `.notDetermined`; on `.denied`
            // it returns false with no dialog. The caller (Mic step) is responsible
            // for branching `.denied` to the Settings deep link instead.
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted ? .granted : .denied)
                }
            }
        case .accessibility:
            // Prompts + pre-lists the app in the Accessibility pane.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            completion(status(for: kind))
        }
    }
}

// MARK: - Manager

/// Observable aggregate of the three permission statuses. Drives both launch
/// gating and the onboarding wizard. All `@Published` mutation happens on the
/// main thread.
final class PermissionsManager: ObservableObject {

    /// Current status of every permission. Always carries an entry for each kind.
    @Published private(set) var statuses: [PermissionKind: PermissionStatus]

    /// Fired once per permission the moment it flips to `.granted` (during a
    /// `refresh()`). Used to auto-advance the wizard and retry the key tap.
    var onPermissionGranted: ((PermissionKind) -> Void)?

    /// Called at the end of every `refresh()` tick. Lets the onboarding controller
    /// run extra liveness probes the checker can't express — notably attempting the
    /// event tap, since `CGPreflightListenEventAccess()` caches `false` per-process
    /// and never reports a live Input-Monitoring grant.
    var onRefresh: (() -> Void)?

    private let checker: PermissionChecking
    private var pollTimer: Timer?
    /// Kinds confirmed granted out-of-band (e.g. the event tap installed). Sticky,
    /// so a subsequent refresh whose checker still lies (cached preflight) doesn't
    /// flip them back to denied.
    private var grantedOverrides: Set<PermissionKind> = []

    init(checker: PermissionChecking = SystemPermissionChecker()) {
        self.checker = checker
        self.statuses = Dictionary(uniqueKeysWithValues:
            PermissionKind.allCases.map { ($0, checker.status(for: $0)) })
    }

    // MARK: Aggregates

    var allGranted: Bool {
        PermissionKind.allCases.allSatisfy { statuses[$0] == .granted }
    }

    /// Kinds not yet granted, in wizard order.
    var missing: [PermissionKind] {
        PermissionKind.allCases.filter { statuses[$0] != .granted }
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .denied
    }

    /// Pure gating rule: show onboarding whenever anything is not granted
    /// (mic `.notDetermined` counts as needing onboarding). No persisted flag —
    /// gating derives from live status so it self-heals if a permission is revoked.
    static func shouldShowOnboarding(statuses: [PermissionKind: PermissionStatus]) -> Bool {
        !PermissionKind.allCases.allSatisfy { statuses[$0] == .granted }
    }

    var shouldShowOnboarding: Bool {
        Self.shouldShowOnboarding(statuses: statuses)
    }

    // MARK: Refresh

    /// Re-read every status; publish the change and fire `onPermissionGranted`
    /// for each permission that newly became granted. Must run on the main thread.
    func refresh() {
        var updated = Dictionary(uniqueKeysWithValues:
            PermissionKind.allCases.map { ($0, checker.status(for: $0)) })
        for kind in grantedOverrides { updated[kind] = .granted }   // sticky confirmations win
        let newlyGranted = Self.newlyGranted(from: statuses, to: updated)
        if newlyGranted.isEmpty == false || updated != statuses {
            statuses = updated
            for kind in newlyGranted { onPermissionGranted?(kind) }
        }
        onRefresh?()
    }

    /// Force a kind to granted out-of-band. Ground truth for Input Monitoring: if
    /// the event tap actually installs, the permission is effectively granted even
    /// while `CGPreflightListenEventAccess()` still (wrongly) reports `false`.
    func markGranted(_ kind: PermissionKind) {
        grantedOverrides.insert(kind)
        guard statuses[kind] != .granted else { return }
        statuses[kind] = .granted
        onPermissionGranted?(kind)
    }

    /// Pure diff: which kinds went from not-granted to `.granted`. Testable in isolation.
    static func newlyGranted(from old: [PermissionKind: PermissionStatus],
                             to new: [PermissionKind: PermissionStatus]) -> [PermissionKind] {
        PermissionKind.allCases.filter { old[$0] != .granted && new[$0] == .granted }
    }

    // MARK: Requesting

    func request(_ kind: PermissionKind) {
        checker.request(kind) { [weak self] _ in self?.refresh() }
    }

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Polling

    /// Start the 1s no-prompt poll. Block-based with a weak self so the timer
    /// never retains the manager (caller still owns start/stop lifetime).
    func startPolling() {
        guard pollTimer == nil else { return }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit { pollTimer?.invalidate() }
}
