import SwiftUI
import Cocoa
import Combine

// MARK: - Onboarding palette
//
// Mockup-specific colours (mockups/onboarding-flow-mockup.html). Where the
// mockup and the existing HUD palette diverge, the mockup wins for fidelity.
private enum OB {
    static let winTop      = Color(hex: 0x23262F)
    static let winBottom   = Color(hex: 0x1E2129)
    static let accent      = Color(hex: 0x5EEAD4)   // mockup teal
    static let accentDeep  = Color(hex: 0x14B8A6)   // button fill
    static let text        = Color(hex: 0xE8EAF0)
    static let textDim     = Color(hex: 0x9AA3B2)
    static let textFaint   = Color(hex: 0x6B7484)
    static let ok          = Color(hex: 0x34D399)
    static let orbit1      = Color(hex: 0x19D7DE)
    static let orbit2      = Color(hex: 0x8C5CFF)
    static let orbit3      = Color(hex: 0xFFB23F)
    static let cardBg      = Color.white.opacity(0.03)
    static let cardStroke  = Color.white.opacity(0.07)

    static let orbitGradient = LinearGradient(
        colors: [orbit1, orbit2, orbit3], startPoint: .leading, endPoint: .trailing)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255)
    }
}

// MARK: - Steps

/// The five wizard screens, in order. The `rawValue` is also the progress index.
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case triggerKey
    case done

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }

    /// The permission a step gates on, if any.
    var permission: PermissionKind? {
        switch self {
        case .microphone:    return .microphone
        case .accessibility: return .accessibility
        default:             return nil
        }
    }
}

// MARK: - View model

/// Pure-ish driver for the wizard: owns the current `step`, the trigger-key
/// selection, and the re-entry / auto-advance logic. Holds a `PermissionsManager`
/// (itself injectable) so this is testable without the real OS APIs.
final class OnboardingViewModel: ObservableObject {
    @Published var step: OnboardingStep
    @Published var selectedKey: TriggerKey
    /// Mic is `.denied` (vs `.notDetermined`) → the "Allow" button must deep-link
    /// to Settings instead of calling `requestAccess` (which would no-op silently).
    @Published var micDenied: Bool
    /// Set when Accessibility was granted but the key tap could not be created
    /// live — the step then asks the user to relaunch.
    @Published var relaunchRequired = false

    let permissions: PermissionsManager

    /// True when the wizard opened mid-flow (some permissions already granted) —
    /// i.e. the user has onboarded before and something was revoked. Re-entry
    /// skips the trigger-key step after the last grant and lands on Done, whose
    /// live try-field lets the user immediately verify the fix worked.
    private(set) var isReentry: Bool

    init(permissions: PermissionsManager) {
        self.permissions = permissions
        self.selectedKey = Config.triggerKey
        self.micDenied = permissions.status(for: .microphone) == .denied
        let initial = Self.initialStep(statuses: permissions.statuses)
        self.step = initial
        self.isReentry = initial != .welcome
    }

    // MARK: Re-entry

    /// Where to open the wizard given current grants:
    /// - everything granted → `.done`
    /// - nothing granted (fresh) → `.welcome`
    /// - partially granted → the first still-missing permission (skip welcome + granted)
    static func initialStep(statuses: [PermissionKind: PermissionStatus]) -> OnboardingStep {
        let missing = PermissionKind.allCases.filter { statuses[$0] != .granted }
        if missing.isEmpty { return .done }
        if missing.count == PermissionKind.allCases.count { return .welcome }
        return step(for: missing[0])
    }

    static func step(for kind: PermissionKind) -> OnboardingStep {
        switch kind {
        case .microphone:    return .microphone
        case .accessibility: return .accessibility
        }
    }

    /// Recompute the entry step (called each time the window is shown).
    func resetToInitialStep() {
        micDenied = permissions.status(for: .microphone) == .denied
        step = Self.initialStep(statuses: permissions.statuses)
        isReentry = step != .welcome
    }

    // MARK: Advance

    func advance() {
        if let next = step.next { step = next }
    }

    /// A permission flipped to granted (from polling). Auto-advance only when the
    /// user is actually sitting on that permission's step — to the next missing
    /// permission, or past them: fresh onboarding continues to the trigger-key
    /// step; re-entry jumps straight to Done so the try-field proves the fix.
    func handleGranted(_ kind: PermissionKind) {
        if kind == .microphone { micDenied = false }
        guard step == Self.step(for: kind) else { return }
        if let firstMissing = permissions.missing.first {
            step = Self.step(for: firstMissing)
        } else {
            step = isReentry ? .done : .triggerKey
        }
    }

    // MARK: Step actions

    func tapMicrophone() {
        // `.notDetermined` → native dialog; `.denied` → Settings (requestAccess no-ops).
        if permissions.status(for: .microphone) == .denied {
            permissions.openSettings(for: .microphone)
        } else {
            permissions.request(.microphone)
        }
    }

    /// Fire the native request (pre-lists ZeroG in the pane + shows the OS
    /// "…would like to…" prompt) and then open the pane — so the app is already
    /// listed with a toggle when the user arrives, no "+ and hunt" friction.
    func requestAndOpenSettings(for step: OnboardingStep) {
        guard let kind = step.permission else { return }
        // request() (AXIsProcessTrustedWithOptions prompt) pre-lists ZeroG in the
        // Accessibility pane so the toggle is already there. Grant detection is the
        // 1s poll reading AXIsProcessTrusted — never the tap (tapCreate can succeed
        // with events withheld, so it proves nothing about the grant).
        permissions.request(kind)
        permissions.openSettings(for: kind)
    }

    func chooseKeyAndAdvance() {
        Config.setTriggerKey(selectedKey)
        advance()
    }

    var triggerGlyph: String { Self.glyph(for: selectedKey) }

    static func glyph(for key: TriggerKey) -> String {
        switch key.id {
        case "leftControl", "rightControl": return "⌃"
        case "leftOption", "rightOption":   return "⌥"
        case "rightShift":                  return "⇧"
        case "fn":                          return "🌐"
        default:                            return "⌃"
        }
    }
}

// MARK: - Icon loading

/// Loads a HUDIcons / asset PNG by URL (there is no asset catalog at runtime —
/// `.process("Resources")` ships loose files, so `Image("name")` renders nothing).
private struct AssetImage: View {
    let resource: String
    var subdirectory: String = "HUDIcons"
    var body: some View {
        if let image = Self.load(resource, subdirectory) {
            Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
        }
    }
    static func load(_ name: String, _ subdir: String) -> NSImage? {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: "png", subdirectory: subdir)
            ?? bundle.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }
}

// MARK: - Staggered entrance

/// Replays the mockup's `riseIn` (fade + 14px rise) each time a step's content
/// is built. Gated on reduce-motion.
private struct RiseIn: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5).delay(delay)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func riseIn(_ delay: Double) -> some View { modifier(RiseIn(delay: delay)) }
}

// MARK: - Segmented progress

/// One capsule per step. Incomplete = plain gray; complete = its slice of a
/// single continuous orbit-gradient sweep (the gradient spans the whole track and
/// shows through only the filled segments). The active segment carries a glow.
private struct SegmentedProgress: View {
    let total: Int
    let currentIndex: Int

    var body: some View {
        ZStack {
            track(fill: false)                 // gray base
            OB.orbitGradient.mask(track(fill: true))   // one sweep, masked to filled segments
            track(activeGlow: true)            // soft glow on the current segment
        }
        .frame(height: 4)
    }

    private func track(fill: Bool = false, activeGlow: Bool = false) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(color(for: i, fill: fill, activeGlow: activeGlow))
                    .shadow(color: activeGlow && i == currentIndex ? OB.accent.opacity(0.55) : .clear,
                            radius: 5)
            }
        }
    }

    private func color(for i: Int, fill: Bool, activeGlow: Bool) -> Color {
        if activeGlow { return .clear }
        if fill { return i <= currentIndex ? .white : .clear }
        return Color.white.opacity(0.08)
    }
}

// MARK: - Icon halo

/// Soft ring behind each stage icon: radial bg + a rotating accent arc + breathe.
/// Switches to a green celebration (ripple + ✓ badge) when granted.
private struct IconHalo: View {
    let iconName: String
    var granted: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotate = false
    @State private var breathe = false
    @State private var ripple = false
    @State private var badgePop = false

    private var ringColor: Color { granted ? OB.ok : OB.accent }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [ringColor.opacity(granted ? 0.20 : 0.16), ringColor.opacity(0.015)],
                    center: UnitPoint(x: 0.5, y: 0.36), startRadius: 2, endRadius: 60))
                .overlay(Circle().stroke(ringColor.opacity(granted ? 0.4 : 0.2), lineWidth: 1))

            // rotating accent arc
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.clear, ringColor.opacity(0.55), .clear],
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(90)),
                    lineWidth: 2)
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .opacity(granted ? 0 : 0.55)

            if granted {
                Circle().stroke(OB.ok, lineWidth: 2)
                    .scaleEffect(ripple ? 1.5 : 0.85)
                    .opacity(ripple ? 0 : 0.85)
            }

            AssetImage(resource: iconName)
                .frame(width: 60, height: 60)
                .shadow(color: ringColor.opacity(0.2), radius: 8, y: 4)

            if granted {
                badge
            }
        }
        .frame(width: 108, height: 108)
        .shadow(color: granted ? .clear : OB.accent.opacity(breathe ? 0.06 : 0.0),
                radius: breathe ? 18 : 0)
        .onAppear(perform: animate)
    }

    private var badge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .heavy))
            .foregroundColor(Color(hex: 0x04211C))
            .frame(width: 32, height: 32)
            .background(Circle().fill(OB.ok))
            .overlay(Circle().stroke(OB.winBottom, lineWidth: 3))
            .offset(x: 38, y: 38)
            .scaleEffect(badgePop ? 1 : 0.3)
            .opacity(badgePop ? 1 : 0)
    }

    private func animate() {
        if granted {
            withAnimation(.easeOut(duration: 0.75)) { ripple = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { badgePop = true }
            return
        }
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { rotate = true }
        withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) { breathe = true }
    }
}

// MARK: - App mark (welcome)

private struct AppMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floatUp = false
    var body: some View {
        Group {
            if let img = AssetImage.load("icon_128x128", "Assets.xcassets/AppIcon.appiconset") {
                Image(nsImage: img).resizable().scaledToFit()
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
        .offset(y: floatUp ? -6 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.25).repeatForever(autoreverses: true)) { floatUp = true }
        }
    }
}

// MARK: - Done live try-field
//
// A real, focusable text field so the user can test dictation for real on the
// Done step: click in, hold the trigger key, speak — the transcription pastes
// here. Also doubles as a live Accessibility check (paste only works if granted).
private struct LiveTryField: View {
    let keyGlyph: String
    let keyName: String
    @State private var text = ""
    @State private var celebrated = false
    @State private var checkPop = false
    @State private var ripple = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let peaks: [CGFloat] = [7, 11, 9, 14, 10, 16, 12, 16, 10, 14, 9, 11, 7]
    private let durs:  [Double]  = [1.9, 2.3, 1.7, 2.1, 2.5, 1.8, 2.2, 1.8, 2.5, 2.1, 1.7, 2.3, 1.9]

    var body: some View {
        VStack(spacing: 12) {
            Waveform(peaks: peaks, durs: durs)
            TextField("Hold \(keyGlyph) \(keyName) and speak…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(OB.text)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(celebrated ? OB.ok.opacity(0.08) : OB.cardBg))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(celebrated ? OB.ok.opacity(0.7)
                            : (focused ? OB.accent.opacity(0.6) : OB.cardStroke), lineWidth: 1))
                .shadow(color: OB.ok.opacity(celebrated ? 0.22 : 0), radius: 12)

            if celebrated { successRow }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: text) { _, newValue in
            guard !celebrated, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            celebrate()
        }
    }

    // One coordinated success beat: a spring check inside a single soft ring,
    // a green glow on the field, and a real trackpad haptic.
    private var successRow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(OB.ok, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .scaleEffect(ripple ? 1.9 : 0.7)
                    .opacity(ripple ? 0 : 0.8)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(OB.ok)
                    .scaleEffect(checkPop ? 1 : 0.3)
            }
            .frame(width: 22, height: 22)
            Text("That's it. You're ready to go.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OB.ok)
        }
        .transition(.opacity)
    }

    private func celebrate() {
        // Tactile confirmation on trackpads — the most "satisfying" part, and quiet.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)

        guard !reduceMotion else { celebrated = true; checkPop = true; return }
        withAnimation(.easeOut(duration: 0.35)) { celebrated = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.05)) { checkPop = true }
        withAnimation(.easeOut(duration: 0.7).delay(0.05)) { ripple = true }
    }
}

private struct Waveform: View {
    let peaks: [CGFloat]
    let durs: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(peaks.enumerated()), id: \.offset) { i, h in
                Capsule()
                    .fill(LinearGradient(colors: [OB.orbit1, OB.orbit2],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: h)
                    .scaleEffect(y: animating ? 1 : 0.45, anchor: .center)
                    .animation(reduceMotion ? nil :
                        .easeInOut(duration: durs[i]).repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.09), value: animating)
            }
        }
        .frame(height: 20)
        .opacity(0.8)
        .onAppear { animating = true }
    }
}

// MARK: - Trigger-key pill

private struct KeyPill: View {
    let key: TriggerKey
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    private var glyph: String { OnboardingViewModel.glyph(for: key) }
    private var hint: String? { key.id == "leftControl" ? "default" : nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(glyph)
                    .font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? OB.accent : Color.white.opacity(0.07)))
                    .foregroundColor(selected ? Color(hex: 0x04211C) : OB.text)
                Text(key.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OB.text)
                Spacer(minLength: 0)
                if let hint {
                    Text(hint.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(OB.accent.opacity(0.85))
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? OB.accent.opacity(0.1) : (hover ? OB.accent.opacity(0.05) : Color.white.opacity(0.03))))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? OB.accent : (hover ? OB.accent.opacity(0.4) : Color.white.opacity(0.09)),
                        lineWidth: 1.5))
            .offset(y: hover ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18), value: hover)
    }
}

// MARK: - Primary button

private struct PrimaryButton: View {
    let title: String
    var waiting: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(waiting ? Color.white.opacity(0.08) : OB.accentDeep))
                .foregroundColor(waiting ? OB.orbit3 : .white)
        }
        .buttonStyle(.plain)
        .disabled(waiting)
    }
}

// MARK: - Wizard view

struct OnboardingWizardView: View {
    @ObservedObject var model: OnboardingViewModel
    let onClose: () -> Void
    var onRelaunch: () -> Void = {}

    var body: some View {
        ZStack {
            LinearGradient(colors: [OB.winTop, OB.winBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SegmentedProgress(total: OnboardingStep.allCases.count, currentIndex: model.step.rawValue)
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(model.step)   // rebuild on step change → entrance replays

                footer
                    .padding(.horizontal, 34)
                    .padding(.bottom, 30)
                    .id(model.step)
            }
        }
        .frame(width: 470, height: 590)
    }

    // MARK: Content per step

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            switch model.step {
            case .welcome:         welcome
            case .microphone,
                 .accessibility:   permissionStep
            case .triggerKey:      triggerKeyStep
            case .done:            doneStep
            }
        }
        .padding(.horizontal, 34)
        .multilineTextAlignment(.center)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .foregroundColor(OB.accent)
            .padding(.bottom, 16)   // mockup eyebrow margin; clears the floating app mark
            .riseIn(0.02)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 23, weight: .bold))
            .foregroundColor(OB.text)
    }

    private func sub(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(OB.textDim)
            .lineSpacing(3)
            .frame(maxWidth: 300)
    }

    // Welcome
    private var welcome: some View {
        VStack(spacing: 0) {
            eyebrow("Welcome")
            AppMark().padding(.bottom, 22).riseIn(0.08)
            title("Voice typing, anywhere").riseIn(0.14)
            sub("Hold a key, speak, and release. Your words land wherever your cursor is.")
                .padding(.top, 8).riseIn(0.20)
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundColor(OB.textFaint)
                Text("Runs entirely on your Mac. Your audio never leaves it.")
                    .font(.system(size: 11)).foregroundColor(OB.textFaint)
            }
            .padding(.top, 18).riseIn(0.26)
        }
    }

    // Microphone / Input Monitoring / Accessibility
    private var permissionStep: some View {
        let kind = model.step.permission!
        let index = (PermissionKind.allCases.firstIndex(of: kind) ?? 0) + 1
        let granted = model.permissions.status(for: kind) == .granted
        return VStack(spacing: 0) {
            eyebrow("Permission \(index) of \(PermissionKind.allCases.count)")
            IconHalo(iconName: kind.iconName, granted: granted)
                .padding(.bottom, 22).riseIn(0.08)
            title(kind.displayName).riseIn(0.14)
            sub(granted ? "Access granted. You can move on." : kind.explanation)
                .padding(.top, 8).riseIn(0.20)
        }
    }

    // Trigger key
    private var triggerKeyStep: some View {
        VStack(spacing: 0) {
            eyebrow("Almost done")
            title("Pick your trigger key").riseIn(0.08)
            sub("Hold it to record, release to transcribe. Pick one you won't press by accident.")
                .padding(.top, 8).riseIn(0.14)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                      spacing: 9) {
                ForEach(TriggerKey.allOptions, id: \.id) { key in
                    KeyPill(key: key, selected: model.selectedKey == key) {
                        model.selectedKey = key
                    }
                }
            }
            .padding(.top, 20).riseIn(0.20)
        }
    }

    // Done
    private var doneStep: some View {
        VStack(spacing: 0) {
            eyebrow("You're ready")
            IconHalo(iconName: "hud-success", granted: true)
                .padding(.bottom, 22).riseIn(0.08)
            title("All set").riseIn(0.14)
            (Text("Try it now. Hold ")
                + Text("\(model.triggerGlyph) \(model.selectedKey.displayName)").bold()
                + Text(" and speak."))
                .font(.system(size: 13))
                .foregroundColor(OB.textDim)
                .frame(maxWidth: 300)
                .padding(.top, 8).riseIn(0.20)
            LiveTryField(keyGlyph: model.triggerGlyph, keyName: model.selectedKey.displayName)
                .padding(.top, 20).riseIn(0.26)
        }
    }

    // MARK: Footer per step

    @ViewBuilder private var footer: some View {
        switch model.step {
        case .welcome:
            VStack(spacing: 0) {
                PrimaryButton(title: "Get started") { model.advance() }.riseIn(0.30)
                Text("Two quick permissions. About a minute.")
                    .font(.system(size: 11)).foregroundColor(OB.textFaint)
                    .padding(.top, 12).riseIn(0.36)
            }
        case .microphone:
            micFooter
        case .accessibility:
            settingsFooter
        case .triggerKey:
            PrimaryButton(title: "Use \(model.selectedKey.displayName)") { model.chooseKeyAndAdvance() }
                .riseIn(0.30)
        case .done:
            PrimaryButton(title: "Start using ZeroG") { onClose() }.riseIn(0.30)
        }
    }

    @ViewBuilder private var micFooter: some View {
        if model.permissions.status(for: .microphone) == .granted {
            PrimaryButton(title: "Continue") { model.advance() }.riseIn(0.30)
        } else if model.micDenied {
            VStack(spacing: 0) {
                PrimaryButton(title: "Open System Settings") { model.tapMicrophone() }.riseIn(0.30)
                Text("Turn on the ZeroG toggle, then come back. We'll detect it for you.")
                    .font(.system(size: 11)).foregroundColor(OB.textFaint)
                    .padding(.top, 12).riseIn(0.36)
            }
        } else {
            PrimaryButton(title: "Allow Microphone") { model.tapMicrophone() }.riseIn(0.30)
        }
    }

    @ViewBuilder private var settingsFooter: some View {
        let granted = model.step.permission.map { model.permissions.status(for: $0) == .granted } ?? false
        // relaunchRequired must win over granted: it's set precisely when AX reports
        // granted but the tap can't come up, so checking granted first would show
        // "Continue" into a dead hotkey and the relaunch affordance could never render.
        if model.step == .accessibility && model.relaunchRequired {
            VStack(spacing: 0) {
                PrimaryButton(title: "Relaunch ZeroG") { onRelaunch() }.riseIn(0.30)
                Text("Accessibility is on, but ZeroG needs a restart to use it.")
                    .font(.system(size: 11)).foregroundColor(OB.orbit3)
                    .padding(.top, 12).riseIn(0.36)
            }
        } else if granted {
            PrimaryButton(title: "Continue") { model.advance() }.riseIn(0.30)
        } else {
            VStack(spacing: 0) {
                PrimaryButton(title: "Open System Settings") { model.requestAndOpenSettings(for: model.step) }.riseIn(0.30)
                Text("Turn on the ZeroG toggle, then come back. We'll detect it for you.")
                    .font(.system(size: 11)).foregroundColor(OB.textFaint)
                    .padding(.top, 12).riseIn(0.36)
            }
        }
    }
}

// MARK: - Window controller

/// Owns the single reused onboarding `NSWindow`. Polls permissions only while the
/// window is open; reuses the same window on re-show (never re-creates).
final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private let permissions: PermissionsManager
    private var window: NSWindow?
    private(set) var model: OnboardingViewModel?

    /// Tears down any existing key tap and installs a fresh one; returns whether it
    /// is now live. Used only AFTER an Accessibility grant to bring the hotkey up —
    /// never as a permission check (tapCreate can succeed with events withheld, so
    /// its success proves nothing about the grant). Wired by the app.
    var attemptKeyTap: (() -> Bool)?

    /// Called after the wizard closes and the app has reverted to `.accessory`.
    /// Lets the app rebuild the key tap, which the activation-policy switch
    /// (`.regular` → `.accessory`) leaves in a dead state. Wired by the app.
    var onClose: (() -> Void)?

    init(permissions: PermissionsManager) {
        self.permissions = permissions
        super.init()
    }

    /// Relaunch the app — the reliable escape when a freshly-granted Accessibility
    /// permission can't be adopted by the running process.
    func relaunchApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Show (or re-show) the wizard at the first relevant step.
    func show() {
        permissions.refresh()
        if window == nil { buildWindow() }
        model?.resetToInitialStep()

        // Become a regular app for the duration of onboarding: Dock icon, a real
        // window, and an app menu — so the wizard is discoverable instead of a
        // hidden menu-bar-only surface. Reverted to .accessory on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        permissions.startPolling()
    }

    /// Forward a granted permission to the live wizard (auto-advance); on the
    /// Accessibility grant, also bring the key tap up. Safe when the window is closed.
    func handlePermissionGranted(_ kind: PermissionKind) {
        if kind == .accessibility {
            // The grant is detected by AXIsProcessTrusted() (the poll) — a real
            // toggle, since a fresh process reads false until it's on. Install the
            // key tap now so events flow. If it can't come up live, ask to relaunch
            // and stay on the step rather than advancing into a dead hotkey.
            let live = (attemptKeyTap?() == true)
            Log.error("Permissions", "Accessibility granted (AX) — key tap live=\(live)")
            guard live else { model?.relaunchRequired = true; return }
        }
        model?.handleGranted(kind)
        // A grant means the user just finished in the native dialog or in System
        // Settings — pull the wizard back to the front so it isn't lost behind
        // other windows on the next step.
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func buildWindow() {
        let model = OnboardingViewModel(permissions: permissions)
        self.model = model

        let root = OnboardingWizardView(
            model: model,
            onClose: { [weak self] in self?.window?.close() },
            onRelaunch: { [weak self] in self?.relaunchApp() })
        let hosting = NSHostingView(rootView: root)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 590),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        win.title = "ZeroG Setup"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(OB.winBottom)
        win.isReleasedWhenClosed = false      // we keep the instance alive and reuse it
        win.contentView = hosting
        win.delegate = self
        win.center()
        self.window = win
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        permissions.stopPolling()             // no zombie polling after close
        NSApp.setActivationPolicy(.accessory) // back to menu-bar-only
        onClose?()                            // rebuild the key tap (policy switch kills it)
    }
}
