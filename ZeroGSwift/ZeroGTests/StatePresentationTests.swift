import Foundation
import SwiftUI
import Testing
@testable import ZeroG

@Suite
struct StatePresentationTests {

    @Test("Loading and idle hide the HUD and show no icon")
    func quietStates() {
        for state in [AppState.loading("x"), .idle] {
            let p = state.presentation(useGemini: false)
            #expect(p.showsHUD == false)
            #expect(p.hudIconName == nil)
            #expect(p.glowColor == Color.clear)
            #expect(p.borderColor == HUDColors.border)
        }
        #expect(AppState.loading("x").presentation(useGemini: false).menuSymbol == "arrow.down.circle")
        #expect(AppState.idle.presentation(useGemini: false).menuSymbol == "mic")
    }

    @Test("Recording uses the voice icon and teal accent; Gemini swaps to the polish icon")
    func recording() {
        let plain = AppState.recording.presentation(useGemini: false)
        #expect(plain.menuSymbol == "mic.fill")
        #expect(plain.showsHUD)
        #expect(plain.hudIconName == "hud-recording")
        #expect(plain.hudStatus == "RECORDING...")
        #expect(plain.statusColor == HUDColors.voiceTeal)
        #expect(plain.glowColor == HUDColors.voiceTeal)

        let gemini = AppState.recording.presentation(useGemini: true)
        #expect(gemini.hudIconName == "hud-polish")
        // The accent stays teal while recording even in Gemini mode — only the icon changes.
        #expect(gemini.glowColor == HUDColors.voiceTeal)
    }

    @Test("Processing accent is amber normally and violet in Gemini mode")
    func processing() {
        let plain = AppState.processing.presentation(useGemini: false)
        #expect(plain.menuSymbol == "waveform.circle")
        #expect(plain.hudIconName == "hud-processing")
        #expect(plain.hudStatus == "TRANSCRIBING...")
        #expect(plain.glowColor == HUDColors.orbitAmber)

        let gemini = AppState.processing.presentation(useGemini: true)
        #expect(gemini.hudIconName == "hud-polish")
        #expect(gemini.glowColor == HUDColors.polishViolet)
    }

    @Test("Success shows only a status row")
    func success() {
        let p = AppState.success.presentation(useGemini: false)
        #expect(p.menuSymbol == "checkmark.circle")
        #expect(p.hudIconName == "hud-success")
        #expect(p.hudTitle == nil)
        #expect(p.hudStatus == "DONE ✓")
        #expect(p.glowColor == HUDColors.successGreen)
    }

    @Test("Error surfaces the message, uppercased, with an ERROR title")
    func error() {
        let p = AppState.error("Mic busy").presentation(useGemini: false)
        #expect(p.menuSymbol == "exclamationmark.triangle")
        #expect(p.hudIconName == "hud-error")
        #expect(p.hudTitle == "ERROR")
        #expect(p.hudStatus == "MIC BUSY")
        #expect(p.glowColor == HUDColors.errorRose)
    }

    @Test("needsPermission is a visible amber notice with the clipboard message")
    func needsPermission() {
        let p = AppState.needsPermission("Grant Accessibility to paste").presentation(useGemini: false)
        #expect(p.showsHUD)
        #expect(p.hudIconName == "onboard-paste")
        #expect(p.hudTitle == "CLICK TO FIX PERMISSIONS")
        #expect(p.hudStatus == "COPIED. PRESS ⌘V")
        #expect(p.glowColor == HUDColors.orbitAmber)
    }
}
