import SwiftUI
import CoreBluetooth

/// Displayed when the treadmill is running (speed > 0).
struct RunningView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService

    @State private var sliderSpeed: Double = 0
    @State private var isDragging: Bool = false

    var body: some View {
        let state = walkingPadService.lastStatus()
        let currentSpeed = Double(state?.speed ?? 0) / 10.0

        VStack(spacing: 6) {
            WorkoutStateView()

            // Speed control
            VStack(spacing: 0) {
                Text(String(format: "%.1f", sliderSpeed))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                Text("km/h")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Slider(value: $sliderSpeed, in: 0.5...8.0, step: 0.5) {
                    SwiftUI.EmptyView()
                } onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        walkingPadService.command()?.setSpeed(speed: UInt8(sliderSpeed * 10))
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            // Mode + Stop row
            HStack(spacing: 6) {
                if state?.walkingMode != nil {
                    modeButton(.manual, current: state?.walkingMode)
                    modeButton(.automatic, current: state?.walkingMode)
                }
            }

            Button(action: {
                walkingPadService.command()?.setSpeed(speed: 0)
            }) {
                Text("Stop")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(.red.opacity(0.1)).interactive(), in: .capsule)
        }
        .onAppear { sliderSpeed = max(currentSpeed, 0.5) }
        .onChange(of: state?.speed) { _, newSpeed in
            guard !isDragging else { return }
            let reported = Double(newSpeed ?? 0) / 10.0
            if reported > 0 && abs(reported - sliderSpeed) > 0.05 {
                sliderSpeed = reported
            }
        }
    }

    private func modeButton(_ mode: WalkingMode, current: WalkingMode?) -> some View {
        Button(action: { walkingPadService.command()?.setWalkingMode(mode: mode) }) {
            Text(mode == .manual ? "Manual" : "Auto")
                .font(.caption2.weight(.medium))
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .glassEffect(
            mode == current ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .capsule
        )
    }
}
