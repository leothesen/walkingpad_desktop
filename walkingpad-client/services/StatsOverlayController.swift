import Cocoa
import SwiftUI

class StatsOverlayController: ObservableObject {
    static let shared = StatsOverlayController()
    
    @Published private(set) var isVisible: Bool = false
    private var window: NSWindow?
    
    func toggle(workout: Workout, walkingPadService: WalkingPadService) {
        if isVisible {
            hide()
        } else {
            show(workout: workout, walkingPadService: walkingPadService)
        }
    }
    
    func show(workout: Workout, walkingPadService: WalkingPadService) {
        guard !isVisible else { return }
        
        let overlayView = StatsOverlayView(workout: workout, walkingPadService: walkingPadService)
        
        let hostingView = NSHostingView(rootView: overlayView)
        // Auto-size the hosting view to fit the SwiftUI content
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 70)
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 70),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.contentView = hostingView
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        // Restore position or use default
        if let savedX = UserDefaults.standard.object(forKey: "StatsOverlayX") as? CGFloat,
           let savedY = UserDefaults.standard.object(forKey: "StatsOverlayY") as? CGFloat {
            window.setFrameOrigin(NSPoint(x: savedX, y: savedY))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.maxX - windowFrame.width - 40
            let y = screenFrame.minY + 40
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.isVisible = true
        
        // Setup position saving
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove), name: NSWindow.didMoveNotification, object: window)
    }
    
    @objc private func windowDidMove(notification: Notification) {
        if let window = notification.object as? NSWindow {
            UserDefaults.standard.set(window.frame.origin.x, forKey: "StatsOverlayX")
            UserDefaults.standard.set(window.frame.origin.y, forKey: "StatsOverlayY")
        }
    }
    
    func hide() {
        if let window = window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: window)
            window.close()
        }
        window = nil
        self.isVisible = false
    }
}
