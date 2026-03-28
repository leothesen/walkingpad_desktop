import SwiftUI
import CoreBluetooth

/// Displayed when the treadmill is running (speed > 0).
/// Shows distance up top, a speed slider, walking mode toggle, and stop button.
struct RunningView: View {
    @EnvironmentObject
    var walkingPadService: WalkingPadService

    /// Local slider state — snaps to 0.5 km/h increments, only sends BLE command on release.
    @State private var sliderSpeed: Double = 0
    @State private var isDragging: Bool = false

    var body: some View {
        let state = self.walkingPadService.lastStatus()
        let currentSpeed = Double(state?.speed ?? 0) / 10.0

        VStack(spacing: 10) {
            WorkoutStateView()

            // Speed slider with label — only sends BLE command when the user releases
            VStack(spacing: 4) {
                Text(String(format: "%.1f km/h", sliderSpeed))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                Slider(value: $sliderSpeed, in: 0.5...8.0, step: 0.5) {
                    EmptyView()
                } onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        let rawSpeed = UInt8(sliderSpeed * 10)
                        walkingPadService.command()?.setSpeed(speed: rawSpeed)
                    }
                }

                HStack {
                    Text("0.5")
                    Spacer()
                    Text("8.0")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))

            // Walking mode toggle
            if state?.walkingMode != nil {
                HStack(spacing: 8) {
                    modeButton(.manual, current: state?.walkingMode)
                    modeButton(.automatic, current: state?.walkingMode)
                }
            }

            // Stop button
            Button(action: {
                self.walkingPadService.command()?.setSpeed(speed: 0)
            }) {
                Text("Stop")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(.red.opacity(0.15)).interactive(), in: .capsule)
        }
        .onAppear {
            sliderSpeed = max(currentSpeed, 0.5)
        }
        .onChange(of: state?.speed) { _, newSpeed in
            // Sync slider when the treadmill reports a speed change, but not while the user is dragging
            guard !isDragging else { return }
            let reported = Double(newSpeed ?? 0) / 10.0
            if reported > 0 && abs(reported - sliderSpeed) > 0.05 {
                sliderSpeed = reported
            }
        }
    }

    private func modeButton(_ mode: WalkingMode, current: WalkingMode?) -> some View {
        Button(action: { walkingPadService.command()?.setWalkingMode(mode: mode) }) {
            Text(mode == .manual ? "Manual" : "Automatic")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(
            mode == current ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .capsule
        )
    }
}
