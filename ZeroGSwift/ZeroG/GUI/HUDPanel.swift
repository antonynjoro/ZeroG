import SwiftUI
import Cocoa
import Combine

// MARK: - HUD State Colors (ZeroG Brand)

private enum HUDColors {
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

// MARK: - HUD SwiftUI View

/// The floating HUD pill that displays recording state.
/// Replaces the Python WebKit/HTML/Tailwind HUD with native SwiftUI — no WebKit process needed.
struct HUDContentView: View {
    @ObservedObject var stateMachine: AppStateMachine
    
    /// Animated glow intensity from audio level.
    @State private var glowIntensity: CGFloat = 0.0
    @State private var processingPulse: CGFloat = 0.0
    
    var body: some View {
        HStack(spacing: 8) {
            // Left: Animated icon
            iconView
                .frame(width: 40, height: 40)
            
            // Right: Status labels
            labelsView
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 210, height: 48)
        .background(HUDColors.hudBase)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: glowColor.opacity(Double(shadowIntensity) * 0.6), radius: CGFloat(10 + shadowIntensity * 30))
        .onReceive(stateMachine.$audioLevel) { newLevel in
            withAnimation(.easeOut(duration: newLevel > Float(glowIntensity) ? 0.12 : 0.6)) {
                glowIntensity = CGFloat(min(1.0, newLevel * 5.0))
            }
        }
        .onReceive(stateMachine.$currentState) { newState in
            switch newState {
            case .processing:
                startProcessingPulse()
            default:
                processingPulse = 0
                if newState != .recording {
                    glowIntensity = 0
                }
            }
        }
    }
    
    private func startProcessingPulse() {
        processingPulse = 0
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            processingPulse = 1
        }
    }
    
    private var shadowIntensity: CGFloat {
        switch stateMachine.currentState {
        case .processing:
            return 0.18 + processingPulse * 0.12
        default:
            return glowIntensity
        }
    }
    
    private var recordingIconScale: CGFloat {
        1.0 + glowIntensity * 0.075
    }
    
    private var processingIconScale: CGFloat {
        1.0 + processingPulse * 0.035
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private var iconView: some View {
        ZStack {
            switch stateMachine.currentState {
            case .recording:
                HUDIconImage(name: stateMachine.useGemini ? "hud-polish" : "hud-recording")
                    .frame(width: 42, height: 42)
                    .scaleEffect(recordingIconScale)
                
            case .processing:
                HUDIconImage(name: stateMachine.useGemini ? "hud-polish" : "hud-processing")
                    .frame(width: 40, height: 40)
                    .scaleEffect(processingIconScale)
                
            case .success:
                HUDIconImage(name: "hud-success")
                    .frame(width: 36, height: 36)
                
            case .error:
                HUDIconImage(name: "hud-error")
                    .frame(width: 36, height: 36)
                
            case .idle, .loading:
                EmptyView()
            }
        }
    }
    
    // MARK: - Labels View
    
    @ViewBuilder
    private var labelsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch stateMachine.currentState {
            case .recording:
                Text("ZeroG")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.secondaryText)
                    .textCase(.uppercase)
                
                Text("RECORDING...")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.voiceTeal)
                
            case .processing:
                Text("ZeroG")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.secondaryText)
                    .textCase(.uppercase)
                
                Text("TRANSCRIBING...")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.primaryText)
                
            case .success:
                Text("DONE ✓")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.successGreen)
                
            case .error(let message):
                Text("ERROR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.errorRose.opacity(0.8))
                    .textCase(.uppercase)
                
                Text(message.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.primaryText)
                    .lineLimit(1)
                
            case .idle, .loading:
                EmptyView()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var borderColor: Color {
        switch stateMachine.currentState {
        case .recording: return HUDColors.voiceTeal.opacity(0.32)
        case .processing: return (stateMachine.useGemini ? HUDColors.polishViolet : HUDColors.orbitAmber).opacity(0.28)
        case .success: return HUDColors.successGreen.opacity(0.3)
        case .error: return HUDColors.errorRose.opacity(0.34)
        case .idle, .loading: return HUDColors.border
        }
    }
    
    private var glowColor: Color {
        switch stateMachine.currentState {
        case .recording: return HUDColors.voiceTeal
        case .processing: return stateMachine.useGemini ? HUDColors.polishViolet : HUDColors.orbitAmber
        case .success: return HUDColors.successGreen
        case .error: return HUDColors.errorRose
        case .idle, .loading: return .clear
        }
    }
}

private struct HUDIconImage: View {
    let name: String

    var body: some View {
        if let image = loadImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
        }
    }

    private func loadImage() -> NSImage? {
        let bundle = Bundle.module
        let urls = [
            bundle.url(forResource: name, withExtension: "png"),
            bundle.url(forResource: name, withExtension: "png", subdirectory: "HUDIcons")
        ]

        guard let url = urls.compactMap({ $0 }).first else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

// MARK: - HUD Panel Controller

/// Manages the floating NSPanel that hosts the SwiftUI HUD view.
final class HUDPanelController {
    
    // MARK: Properties
    
    private var panel: NSPanel!
    private var isVisible = false
    private var cancellable: AnyCancellable?
    
    private let stateMachine: AppStateMachine
    
    // MARK: Dimensions
    
    private let hudWidth: CGFloat = 525
    private let hudHeight: CGFloat = 300
    
    // MARK: Positioning
    
    private var centerX: CGFloat = 0
    private var visibleY: CGFloat = 0
    private var hiddenY: CGFloat = 0
    
    // MARK: Initialization
    
    init(stateMachine: AppStateMachine) {
        self.stateMachine = stateMachine
        
        setupPanel()
        observeState()
    }
    
    // MARK: - Setup
    
    private func setupPanel() {
        let rect = NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight)
        
        panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        // Create SwiftUI hosting view
        let hudView = HUDContentView(stateMachine: stateMachine)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        
        panel.contentView?.addSubview(hostingView)
        
        updatePosition()
        panel.setFrameOrigin(NSPoint(x: centerX, y: hiddenY))
        
        panel.alphaValue = 0.0
        panel.orderOut(nil)
    }
    
    // MARK: - State Observation
    
    private func observeState() {
        cancellable = stateMachine.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle, .loading:
                    self.slideOut()
                default:
                    self.slideIn()
                }
            }
    }
    
    // MARK: - Positioning
    
    private func updatePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLocation, $0.frame) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        
        let visibleFrame = targetScreen.visibleFrame
        
        centerX = visibleFrame.origin.x + (visibleFrame.size.width - hudWidth) / 2
        visibleY = visibleFrame.origin.y + 120
        hiddenY = visibleFrame.origin.y - hudHeight - 50
    }
    
    // MARK: - Slide Animations
    
    private func slideIn() {
        if isVisible {
            panel.orderFrontRegardless()
            return
        }
        
        updatePosition()
        isVisible = true
        
        let startY = visibleY - 20
        panel.setFrameOrigin(NSPoint(x: centerX, y: startY))
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Timing.hudSlideIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            panel.animator().setFrameOrigin(NSPoint(x: centerX, y: visibleY))
            panel.animator().alphaValue = 1.0
        }
    }
    
    private func slideOut() {
        guard isVisible else { return }
        isVisible = false
        
        panel.ignoresMouseEvents = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Config.Timing.hudSlideOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            panel.animator().setFrameOrigin(NSPoint(x: centerX, y: hiddenY))
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}
