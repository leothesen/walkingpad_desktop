import SwiftUI

/// Root view of the menu bar popover. Only as tall as the current state needs.
struct ContentView: View {
    static let width: CGFloat = 280

    var body: some View {
        DeviceView()
            .padding(14)
            .frame(width: ContentView.width, alignment: .topLeading)
    }
}
