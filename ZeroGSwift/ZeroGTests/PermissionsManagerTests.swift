import Foundation
import Testing
@testable import ZeroG

/// In-memory `PermissionChecking` so the manager can be driven without touching
/// the real AVCaptureDevice / Accessibility APIs.
final class FakePermissionChecker: PermissionChecking {
    var statuses: [PermissionKind: PermissionStatus]
    private(set) var requested: [PermissionKind] = []

    init(_ statuses: [PermissionKind: PermissionStatus] = [:]) {
        // Default everything to denied unless overridden.
        var base = Dictionary(uniqueKeysWithValues:
            PermissionKind.allCases.map { ($0, PermissionStatus.denied) })
        for (k, v) in statuses { base[k] = v }
        self.statuses = base
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .denied
    }

    func request(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void) {
        requested.append(kind)
        completion(statuses[kind] ?? .denied)
    }
}

@Suite
struct PermissionsManagerTests {

    // MARK: Aggregation

    @Test("allGranted is true only when every permission is granted")
    func allGranted() {
        let all: [PermissionKind: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]
        #expect(PermissionsManager(checker: FakePermissionChecker(all)).allGranted)

        let partial = FakePermissionChecker([.microphone: .granted])  // accessibility denied
        #expect(PermissionsManager(checker: partial).allGranted == false)
    }

    @Test("missing lists the not-granted kinds in wizard order")
    func missing() {
        let m = PermissionsManager(checker: FakePermissionChecker([.microphone: .granted]))
        #expect(m.missing == [.accessibility])
    }

    // MARK: Gating

    @Test("shouldShowOnboarding is false only when all granted")
    func gatingAllGranted() {
        let all: [PermissionKind: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]
        #expect(PermissionsManager.shouldShowOnboarding(statuses: all) == false)
    }

    @Test("shouldShowOnboarding is true when mic is merely notDetermined")
    func gatingNotDetermined() {
        let statuses: [PermissionKind: PermissionStatus] = [
            .microphone: .notDetermined, .accessibility: .granted
        ]
        #expect(PermissionsManager.shouldShowOnboarding(statuses: statuses))
    }

    // MARK: Refresh diffing

    @Test("newlyGranted reports only kinds that crossed into granted")
    func newlyGrantedDiff() {
        let old: [PermissionKind: PermissionStatus] = [.microphone: .denied, .accessibility: .notDetermined]
        let new: [PermissionKind: PermissionStatus] = [.microphone: .granted, .accessibility: .denied]
        #expect(PermissionsManager.newlyGranted(from: old, to: new) == [.microphone])
    }

    @Test("refresh fires onPermissionGranted exactly once for a fresh grant")
    func refreshFiresCallbackOnFlip() {
        let checker = FakePermissionChecker()
        let manager = PermissionsManager(checker: checker)
        var fired: [PermissionKind] = []
        manager.onPermissionGranted = { fired.append($0) }

        checker.statuses[.accessibility] = .granted
        manager.refresh()
        #expect(fired == [.accessibility])

        // A second refresh with no change must not re-fire.
        manager.refresh()
        #expect(fired == [.accessibility])
    }

    @Test("refresh fires nothing when nothing changed")
    func refreshNoChange() {
        let manager = PermissionsManager(checker: FakePermissionChecker())
        var fired = false
        manager.onPermissionGranted = { _ in fired = true }
        manager.refresh()
        #expect(fired == false)
    }

    // MARK: Revoke self-healing

    @Test("refresh flips a granted permission back to denied after a revoke")
    func refreshDetectsRevoke() {
        let checker = FakePermissionChecker([.accessibility: .granted])
        let manager = PermissionsManager(checker: checker)
        #expect(manager.status(for: .accessibility) == .granted)
        checker.statuses[.accessibility] = .denied
        manager.refresh()
        #expect(manager.status(for: .accessibility) == .denied)
        #expect(manager.shouldShowOnboarding)
    }

    // MARK: Requesting

    @Test("request routes through the checker and refreshes")
    func requestRoutes() {
        let checker = FakePermissionChecker()
        let manager = PermissionsManager(checker: checker)
        manager.request(.microphone)
        #expect(checker.requested == [.microphone])
    }
}
