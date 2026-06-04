import SwiftUI
import Cocoa
import Combine

// The ZeroG colour palette (`HUDColors`) and the per-state visual descriptor
// (`StatePresentation` via `AppState.presentation(useGemini:)`) live in
// Core/StatePresentation.swift — the single source of truth this view reads.

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

    /// Per-state visual descriptor — the single source of truth (Core/StatePresentation.swift).
    private var presentation: StatePresentation {
        stateMachine.currentState.presentation(useGemini: stateMachine.useGemini)
    }

    /// Scale applied to the icon. Animation-driven, so it stays in the view layer
    /// rather than the static descriptor: recording tracks audio glow, processing pulses.
    private var iconScale: CGFloat {
        switch stateMachine.currentState {
        case .recording: return recordingIconScale
        case .processing: return processingIconScale
        default: return 1.0
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
            if let name = presentation.hudIconName {
                HUDIconImage(name: name)
                    .frame(width: presentation.iconSize, height: presentation.iconSize)
                    .scaleEffect(iconScale)
            }
        }
    }

    // MARK: - Labels View

    @ViewBuilder
    private var labelsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = presentation.hudTitle {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(presentation.titleColor)
                    .textCase(.uppercase)
            }

            if let status = presentation.hudStatus {
                Text(status)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(presentation.statusColor)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Computed Properties

    private var borderColor: Color { presentation.borderColor }

    private var glowColor: Color { presentation.glowColor }
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
