import SwiftUI

// MARK: - HUD Palette (ZeroG Brand)

/// The ZeroG colour palette. Single home for every brand colour the UI uses —
/// referenced by both `StatePresentation` (per-state accents) and the HUD chrome
/// (base, border, text).
enum HUDColors {
    static let hudBase = Color(red: 0.067, green: 0.075, blue: 0.102) // #11131A
    static let border = Color(red: 0.165, green: 0.184, blue: 0.239) // #2A2F3D
    static let primaryText = Color(red: 0.957, green: 0.937, blue: 0.902) // #F4EFE6
    static let secondaryText = Color(red: 0.682, green: 0.714, blue: 0.769) // #AEB6C4
    static let voiceTeal = Color(red: 0.098, green: 0.843, blue: 0.871) // #19D7DE
    static let orbitAmber = Color(red: 1.0, green: 0.698, blue: 0.247) // #FFB23F
    static let polishViolet = Color(red: 0.725, green: 0.486, blue: 1.0) // #B97CFF
    static let successGreen = Color(red: 0.133, green: 0.788, blue: 0.561) // #22C98F
    static let errorRose = Color(red: 1.0, green: 0.416, blue: 0.478) // #FF6A7A
}

// MARK: - State Presentation

/// Everything the UI needs to render a given `AppState` — the *single source of
/// truth* for how a state looks. Adding or changing a state means editing the
/// `AppState` enum and the one `presentation(useGemini:)` switch below; the menu
/// bar and HUD read this descriptor instead of each maintaining their own
/// parallel `switch currentState` blocks.
struct StatePresentation {
    /// SF Symbol for the menu bar (template / monochrome).
    let menuSymbol: String

    /// Whether the floating HUD is shown for this state.
    let showsHUD: Bool

    /// Custom HUD icon asset name; `nil` means no icon (idle / loading).
    let hudIconName: String?
    /// Rendered icon frame size.
    let iconSize: CGFloat

    /// Small top label (e.g. "ZeroG"); `nil` means no title row.
    let hudTitle: String?
    let titleColor: Color

    /// Main status label (e.g. "RECORDING..."); `nil` means no status row.
    let hudStatus: String?
    let statusColor: Color

    /// Glow / shadow colour. `.clear` disables the glow.
    let glowColor: Color
    /// Capsule border colour (opacity already applied).
    let borderColor: Color
}

extension AppState {
    /// Build the presentation for this state. `useGemini` only affects the
    /// recording/processing visuals (polish icon + violet accent).
    func presentation(useGemini: Bool) -> StatePresentation {
        switch self {
        case .loading:
            return StatePresentation(
                menuSymbol: "arrow.down.circle",
                showsHUD: false,
                hudIconName: nil, iconSize: 0,
                hudTitle: nil, titleColor: .clear,
                hudStatus: nil, statusColor: .clear,
                glowColor: .clear, borderColor: HUDColors.border
            )

        case .idle:
            return StatePresentation(
                menuSymbol: "mic",
                showsHUD: false,
                hudIconName: nil, iconSize: 0,
                hudTitle: nil, titleColor: .clear,
                hudStatus: nil, statusColor: .clear,
                glowColor: .clear, borderColor: HUDColors.border
            )

        case .recording:
            return StatePresentation(
                menuSymbol: "mic.fill",
                showsHUD: true,
                hudIconName: useGemini ? "hud-polish" : "hud-recording", iconSize: 42,
                hudTitle: "ZeroG", titleColor: HUDColors.secondaryText,
                hudStatus: "RECORDING...", statusColor: HUDColors.voiceTeal,
                glowColor: HUDColors.voiceTeal,
                borderColor: HUDColors.voiceTeal.opacity(0.32)
            )

        case .processing:
            let accent = useGemini ? HUDColors.polishViolet : HUDColors.orbitAmber
            return StatePresentation(
                menuSymbol: "waveform.circle",
                showsHUD: true,
                hudIconName: useGemini ? "hud-polish" : "hud-processing", iconSize: 40,
                hudTitle: "ZeroG", titleColor: HUDColors.secondaryText,
                hudStatus: "TRANSCRIBING...", statusColor: HUDColors.primaryText,
                glowColor: accent,
                borderColor: accent.opacity(0.28)
            )

        case .success:
            return StatePresentation(
                menuSymbol: "checkmark.circle",
                showsHUD: true,
                hudIconName: "hud-success", iconSize: 36,
                hudTitle: nil, titleColor: .clear,
                hudStatus: "DONE ✓", statusColor: HUDColors.successGreen,
                glowColor: HUDColors.successGreen,
                borderColor: HUDColors.successGreen.opacity(0.3)
            )

        case .error(let message):
            return StatePresentation(
                menuSymbol: "exclamationmark.triangle",
                showsHUD: true,
                hudIconName: "hud-error", iconSize: 36,
                hudTitle: "ERROR", titleColor: HUDColors.errorRose.opacity(0.8),
                hudStatus: message.uppercased(), statusColor: HUDColors.primaryText,
                glowColor: HUDColors.errorRose,
                borderColor: HUDColors.errorRose.opacity(0.34)
            )
        }
    }
}
