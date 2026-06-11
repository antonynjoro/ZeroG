import Foundation
import Testing
@testable import ZeroG

@Suite
struct OnboardingViewModelTests {

    private func manager(_ statuses: [PermissionKind: PermissionStatus]) -> PermissionsManager {
        PermissionsManager(checker: FakePermissionChecker(statuses))
    }

    // MARK: Re-entry step selection

    @Test("All missing → start at Welcome")
    func reentryAllMissing() {
        let step = OnboardingViewModel.initialStep(statuses: FakePermissionChecker().statuses)
        #expect(step == .welcome)
    }

    @Test("Mic granted, accessibility missing → jump to Accessibility")
    func reentryMicGranted() {
        let checker = FakePermissionChecker([.microphone: .granted])
        #expect(OnboardingViewModel.initialStep(statuses: checker.statuses) == .accessibility)
    }

    @Test("All granted → Done")
    func reentryAllGranted() {
        let checker = FakePermissionChecker([.microphone: .granted, .accessibility: .granted])
        #expect(OnboardingViewModel.initialStep(statuses: checker.statuses) == .done)
    }

    @Test("Init places the model at its re-entry step")
    func initUsesReentryStep() {
        let vm = OnboardingViewModel(manager([.microphone: .granted]))
        #expect(vm.step == .accessibility)
    }

    // MARK: Auto-advance
    //
    // In production, PermissionsManager updates `statuses` BEFORE firing
    // onPermissionGranted, so the fakes below reflect the post-grant state.

    @Test("Grant advances to the next still-missing permission")
    func grantAdvancesToNextMissing() {
        // Mic just granted; accessibility still missing.
        let vm = OnboardingViewModel(manager([.microphone: .granted]))
        vm.step = .microphone
        vm.handleGranted(.microphone)
        #expect(vm.step == .accessibility)
    }

    @Test("Fresh onboarding: last grant continues to the trigger-key step")
    func freshFlowContinuesToTriggerKey() {
        let checker = FakePermissionChecker()           // all denied at launch
        let m = PermissionsManager(checker: checker)
        let vm = OnboardingViewModel(permissions: m)
        #expect(vm.step == .welcome)                    // fresh flow, not re-entry

        checker.statuses = [.microphone: .granted, .accessibility: .granted]
        m.refresh()
        vm.step = .accessibility
        vm.handleGranted(.accessibility)
        #expect(vm.step == .triggerKey)
    }

    @Test("Re-entry: last grant jumps straight to Done (live try-field)")
    func reentryJumpsToDone() {
        // Mic already granted at open → wizard re-entered at Accessibility.
        let checker = FakePermissionChecker([.microphone: .granted])
        let m = PermissionsManager(checker: checker)
        let vm = OnboardingViewModel(permissions: m)
        #expect(vm.step == .accessibility)

        checker.statuses[.accessibility] = .granted
        m.refresh()
        vm.handleGranted(.accessibility)
        #expect(vm.step == .done)
    }

    @Test("Re-entry: mic-only revoke lands on Done after the re-grant")
    func reentryMicOnlyRevoke() {
        let checker = FakePermissionChecker([.accessibility: .granted])
        let m = PermissionsManager(checker: checker)
        let vm = OnboardingViewModel(permissions: m)
        #expect(vm.step == .microphone)

        checker.statuses[.microphone] = .granted
        m.refresh()
        vm.handleGranted(.microphone)
        #expect(vm.step == .done)
    }

    @Test("Granting a different permission does not advance")
    func grantOtherStepDoesNotAdvance() {
        let vm = OnboardingViewModel(manager([:]))
        vm.step = .accessibility
        vm.handleGranted(.microphone)
        #expect(vm.step == .accessibility)
    }

    @Test("Granting mic clears the denied flag")
    func grantMicClearsDenied() {
        let vm = OnboardingViewModel(manager([.microphone: .denied]))
        #expect(vm.micDenied)
        vm.handleGranted(.microphone)
        #expect(vm.micDenied == false)
    }

    @Test("Done is the last step; advance past it is a no-op")
    func advancePastDone() {
        let vm = OnboardingViewModel(manager([:]))
        vm.step = .done
        vm.advance()
        #expect(vm.step == .done)
    }

    // MARK: Trigger key glyphs

    @Test("Each trigger key maps to its modifier glyph")
    func triggerGlyphs() {
        #expect(OnboardingViewModel.glyph(for: TriggerKey.from(id: "leftControl")) == "⌃")
        #expect(OnboardingViewModel.glyph(for: TriggerKey.from(id: "rightOption")) == "⌥")
        #expect(OnboardingViewModel.glyph(for: TriggerKey.from(id: "rightShift")) == "⇧")
        #expect(OnboardingViewModel.glyph(for: TriggerKey.from(id: "fn")) == "🌐")
    }
}

private extension OnboardingViewModel {
    convenience init(_ manager: PermissionsManager) { self.init(permissions: manager) }
}
