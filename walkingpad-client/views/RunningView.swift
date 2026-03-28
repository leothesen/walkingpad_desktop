import SwiftUI
import CoreBluetooth

/// Displayed when the treadmill is running (speed > 0).
/// Shows workout stats, a 4x4 speed button grid (manual mode), walking mode toggle, and stop button.
/// Speed buttons range from 1.0 to 8.5 km/h in 0.5 km/h increments.
struct RunningView: View {
    @EnvironmentObject
    var walkingPadService: WalkingPadService

    var body: some View {
        let state = self.walkingPadService.lastStatus()
        let speedLevel = state?.speed ?? 0

        let renderButton = { (speed: Int) in
            Button(action: {
                self.walkingPadService.command()?.setSpeed(speed: UInt8(speed))
            }) {
                Text(String(format: "%.1f", Float(speed) / 10.0))
                    .font(.caption2.weight(.medium))
                    .frame(minWidth: 32)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .glassEffect(
                speedLevel == speed ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 8)
            )
        }

        let renderWalkingModeButton = {(mode: WalkingMode) in
            Button(action: { self.walkingPadService.command()?.setWalkingMode(mode: mode)}) {
                Text(mode == .manual ? "Manual" : "Automatic")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(
                mode == state?.walkingMode ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .capsule
            )
        }

        let renderRow = { (start: Int, end: Int) in
            HStack(spacing: 4) {
                ForEach(start..<end, id: \.self) { index in
                    let targetSpeed = (index * 10) / 2 + 10
                    renderButton(targetSpeed)
                }
            }
        }

        let renderSpeedRows = {
            ForEach(0..<4) { index in
                let start = index * 4
                renderRow(start, start + 4)
            }
        }

        VStack(spacing: 10) {
            WorkoutStateView()

            if (state?.walkingMode == .manual) {
                VStack(spacing: 4) {
                    renderSpeedRows()
                }
            } else {
                Text("Speed: \(String(format: "%.1f km/h", Double(speedLevel) / 10))")
                    .font(.title3.weight(.semibold))
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                renderWalkingModeButton(.manual)
                renderWalkingModeButton(.automatic)
            }

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
    }
}
