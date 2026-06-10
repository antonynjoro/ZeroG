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

    // MARK: markGranted (sticky override)

    @Test("markGranted flips status and fires the callback once")
    func markGrantedFires() {
        let manager = PermissionsManager(checker: FakePermissionChecker())
        var fired: [PermissionKind] = []
        manager.onPermissionGranted = { fired.append($0) }
        manager.markGranted(.accessibility)
        #expect(manager.status(for: .accessibility) == .granted)
        #expect(fired == [.accessibility])
        // Idempotent: already granted → no second callback.
        manager.markGranted(.accessibility)
        #expect(fired == [.accessibility])
    }

    @Test("A marked grant survives a refresh whose checker still reports denied")
    func markGrantedIsSticky() {
        // Simulates AXIsProcessTrusted caching false after the tap actually installed.
        let checker = FakePermissionChecker()   // accessibility stays .denied
        let manager = PermissionsManager(checker: checker)
        manager.markGranted(.accessibility)
        manager.refresh()
        #expect(manager.status(for: .accessibility) == .granted)
    }

    @Test("onRefresh fires on each refresh tick")
    func onRefreshFires() {
        let manager = PermissionsManager(checker: FakePermissionChecker())
        var ticks = 0
        manager.onRefresh = { ticks += 1 }
        manager.refresh()
        manager.refresh()
        #expect(ticks == 2)
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
