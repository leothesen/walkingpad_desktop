import SwiftUI

/// Bottom bar with Stats link, Login/Logout button, and Quit button.
/// Warning: Quit uses exit(0) which bypasses cleanup — see KNOWN_ISSUES.md #8.
struct FooterView: View {
    @EnvironmentObject var walkingPadService: WalkingPadService
    @EnvironmentObject var workout: Workout
    @Environment(\.openURL) var openURL
    
    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                openURL(URL(string: "https://walkingpad-stats.netlify.app")!)
            }) {
                Text("Stats")
            }
            LoginLogoutButton()
            Button(action: {
                walkingPadService.command()?.setSpeed(speed: 0)
                workout.save()
                exit(0)
            }) {
                Text("Quit")
            }
        }
    }
}

struct FooterView_Previews: PreviewProvider {
    static var previews: some View {
        FooterView()
    }
}
