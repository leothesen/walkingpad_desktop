
import SwiftUI

struct WaitingForTreadmillView: View {
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView()
                Text("Waiting for treadmill...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            Spacer()
        }
    }
}

struct SearchingForDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        WaitingForTreadmillView()
    }
}
