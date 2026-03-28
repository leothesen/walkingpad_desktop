import SwiftUI
import AppKit

struct LoginLogoutButton: View {
    @EnvironmentObject var gatewayService: HCGatewayService
    
    var body: some View {
        if (!gatewayService.isLoggedIn()) {
            Button("Login") {
                openLoginWindow()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Button("Logout") {
                gatewayService.logout()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }
    
    private func openLoginWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "Login"
        window.isReleasedWhenClosed = true
        window.level = .floating
        
        let loginView = LoginWindowView(
            gatewayService: gatewayService,
            window: window
        )
        
        let hostingView = NSHostingView(rootView: loginView)
        window.contentView = hostingView
        
        // Show the window and make it key
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        
        // Set focus to username field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hostingView.window?.makeFirstResponder(hostingView)
        }
    }
}
