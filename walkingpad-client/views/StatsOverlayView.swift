import SwiftUI

struct StatsOverlayView: View {
    @StateObject var viewModel: StatsOverlayViewModel
    
    init(workout: Workout, walkingPadService: WalkingPadService) {
        _viewModel = StateObject(wrappedValue: StatsOverlayViewModel(workout: workout, walkingPadService: walkingPadService))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            statItem(value: viewModel.speed, unit: "km/h", icon: "speedometer", color: .blue)
            divider()
            statItem(value: viewModel.distance, unit: "km", icon: "figure.walk", color: .orange)
            divider()
            statItem(value: viewModel.time, unit: "time", icon: "timer", color: .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            ZStack {
                // High-performance blur background
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                
                // Subtle inner glow
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isRunning)
    }
    
    @ViewBuilder
    private func statItem(value: String, unit: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color.opacity(0.8))
            
            VStack(alignment: .leading, spacing: -2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                
                Text(unit)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .frame(minWidth: 70, alignment: .leading)
    }
    
    @ViewBuilder
    private func divider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1)
            .frame(height: 24)
            .padding(.horizontal, 16)
    }
}

// Helper for NSVisualEffectView in SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
