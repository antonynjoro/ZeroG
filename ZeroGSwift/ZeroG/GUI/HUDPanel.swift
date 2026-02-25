import SwiftUI
import Cocoa
import Combine

// MARK: - HUD State Colors (ZeroG Brand)

private enum HUDColors {
    static let voidBlack = Color(red: 0.043, green: 0.043, blue: 0.043) // #0b0b0b
    static let vacuumGrey = Color(red: 0.2, green: 0.2, blue: 0.2)     // #333333
    static let warningGold = Color(red: 1.0, green: 0.843, blue: 0.0)   // #FFD700
    static let signalWhite = Color(red: 0.929, green: 0.929, blue: 0.929) // #EDEDED
    static let linkGreen = Color(red: 0.063, green: 0.725, blue: 0.506)  // Emerald
    static let alertRose = Color(red: 0.957, green: 0.247, blue: 0.369)  // Rose
}

// MARK: - HUD SwiftUI View

/// The floating HUD pill that displays recording state.
/// Replaces the Python WebKit/HTML/Tailwind HUD with native SwiftUI — no WebKit process needed.
struct HUDContentView: View {
    @ObservedObject var stateMachine: AppStateMachine
    
    /// Animated glow intensity from audio level.
    @State private var glowIntensity: CGFloat = 0.0
    @State private var rotationAngle: Double = 0.0
    
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
        .background(HUDColors.voidBlack)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: glowColor.opacity(Double(glowIntensity) * 0.6), radius: CGFloat(10 + glowIntensity * 30))
        .onReceive(stateMachine.$audioLevel) { newLevel in
            withAnimation(.easeOut(duration: newLevel > Float(glowIntensity) ? 0.12 : 0.6)) {
                glowIntensity = CGFloat(min(1.0, newLevel * 5.0))
            }
        }
        .onReceive(stateMachine.$currentState) { newState in
            switch newState {
            case .recording, .processing:
                startSpinning()
            default:
                glowIntensity = 0
            }
        }
    }
    
    private func startSpinning() {
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    // MARK: - Icon View
    
    @ViewBuilder
    private var iconView: some View {
        ZStack {
            switch stateMachine.currentState {
            case .recording:
                // Orbit ring
                Circle()
                    .stroke(HUDColors.warningGold.opacity(0.3), lineWidth: 1)
                
                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(HUDColors.warningGold, lineWidth: 2)
                    .rotationEffect(.degrees(rotationAngle))
                
                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundColor(HUDColors.warningGold)
                
            case .processing:
                Circle()
                    .stroke(HUDColors.warningGold.opacity(0.2), lineWidth: 1)
                
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [HUDColors.warningGold, HUDColors.signalWhite],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
                    .rotationEffect(.degrees(rotationAngle))
                
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HUDColors.signalWhite)
                
            case .success:
                Circle()
                    .fill(HUDColors.linkGreen.opacity(0.1))
                
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(HUDColors.linkGreen)
                
            case .error:
                Circle()
                    .fill(HUDColors.alertRose.opacity(0.1))
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(HUDColors.alertRose)
                
            case .idle:
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
                Text("ZeroG Link")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.signalWhite.opacity(0.6))
                    .textCase(.uppercase)
                
                Text("TRANSMITTING...")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.warningGold)
                
            case .processing:
                Text("PROCESSING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.signalWhite.opacity(0.6))
                    .textCase(.uppercase)
                
                Text("CALCULATING...")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.signalWhite)
                    .opacity(0.8)
                
            case .success:
                Text("ESTABLISHED")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.linkGreen)
                
            case .error(let message):
                Text("TURBULENCE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(HUDColors.alertRose.opacity(0.7))
                    .textCase(.uppercase)
                
                Text(message.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                
            case .idle:
                EmptyView()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var borderColor: Color {
        switch stateMachine.currentState {
        case .recording: return HUDColors.vacuumGrey
        case .processing: return HUDColors.warningGold.opacity(0.3)
        case .success: return HUDColors.linkGreen.opacity(0.3)
        case .error: return HUDColors.alertRose.opacity(0.3)
        case .idle: return HUDColors.vacuumGrey
        }
    }
    
    private var glowColor: Color {
        switch stateMachine.currentState {
        case .recording: return HUDColors.warningGold
        case .processing: return HUDColors.warningGold
        case .success: return HUDColors.linkGreen
        case .error: return HUDColors.alertRose
        case .idle: return .clear
        }
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
                if state == .idle {
                    self.slideOut()
                } else {
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
            context.duration = 0.3
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
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            panel.animator().setFrameOrigin(NSPoint(x: centerX, y: hiddenY))
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}
