#if os(macOS)
import AppKit

/// Dock icon with a green dot while the tunnel is up.
@MainActor enum DockBadge {
    static func update(connected: Bool) {
        guard connected, let base = NSImage(named: NSImage.applicationIconName) else { NSApp.applicationIconImage = nil; return }
        let size = base.size
        NSApp.applicationIconImage = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let d = size.width * 0.26, dot = NSRect(x: rect.maxX - d - size.width * 0.08, y: rect.minY + size.width * 0.08, width: d, height: d)
            NSColor.black.withAlphaComponent(0.55).setFill(); NSBezierPath(ovalIn: dot.insetBy(dx: -d * 0.12, dy: -d * 0.12)).fill()
            NSColor.systemGreen.setFill(); NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }
}
#endif
