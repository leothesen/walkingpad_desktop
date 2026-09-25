import AppKit

/// Draws the menu bar glyph: a ring that fills toward the daily goal.
///
/// - `.progress`: track + arc (idle)
/// - `.walking`: track + arc + a filled centre dot (belt live)
/// - `.goalReached`: solid disc with a knocked-out checkmark
/// - `.disconnected`: dashed ring
///
/// Images are template images, so macOS tints them for light/dark menu bars.
enum StatusBarIcon {
    enum Style: Hashable {
        case progress
        case walking
        case goalReached
        case disconnected
    }

    private static var cache: [String: NSImage] = [:]

    static func image(style: Style, progress: Double) -> NSImage {
        // Quantise so the cache stays small and the ring doesn't redraw every frame.
        let percent = Int((min(max(progress, 0), 1) * 100).rounded())
        let key = "\(style)-\(percent)"
        if let cached = cache[key] { return cached }

        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(style: style, fraction: Double(percent) / 100, in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel(style: style, percent: percent)
        cache[key] = image
        return image
    }

    private static func draw(style: Style, fraction: Double, in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 6
        let lineWidth: CGFloat = 1.8
        let color = NSColor.black

        switch style {
        case .goalReached:
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()

            let check = NSBezierPath()
            check.move(to: NSPoint(x: center.x - 3.4, y: center.y + 0.1))
            check.line(to: NSPoint(x: center.x - 1.0, y: center.y - 2.4))
            check.line(to: NSPoint(x: center.x + 3.6, y: center.y + 2.6))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSGraphicsContext.current?.compositingOperation = .clear
            check.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

        case .disconnected:
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = lineWidth
            ring.setLineDash([2.2, 2.2], count: 2, phase: 0)
            color.withAlphaComponent(0.6).setStroke()
            ring.stroke()

        case .progress, .walking:
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            track.lineWidth = lineWidth
            color.withAlphaComponent(0.28).setStroke()
            track.stroke()

            if fraction > 0 {
                // Clockwise from 12 o'clock.
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }

            if style == .walking {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)).fill()
            }
        }
    }

    private static func accessibilityLabel(style: Style, percent: Int) -> String {
        switch style {
        case .progress: return "WalkingPad, \(percent)% of daily goal"
        case .walking: return "WalkingPad, walking, \(percent)% of daily goal"
        case .goalReached: return "WalkingPad, daily goal reached"
        case .disconnected: return "WalkingPad, not connected"
        }
    }
}
