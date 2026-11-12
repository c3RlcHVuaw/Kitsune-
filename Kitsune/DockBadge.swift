#if os(macOS)
import AppKit
import CoreImage
import SwiftUI

/// Dock icon recoloured to the chosen theme, with a green dot while the tunnel is up; plus the menu bar icon.
@MainActor enum DockBadge {
    /// Hue shift from the original copper icon to each theme, in radians.
    private static func hue(_ theme: ButtonTheme) -> Double {
        switch theme { case .copper: 0; case .moon: 3.32; case .neon: 2.27 }
    }

    static func update(connected: Bool, theme: ButtonTheme) {
        guard let original = NSImage(named: NSImage.applicationIconName) else { return }
        guard connected || theme != .copper else { NSApp.applicationIconImage = nil; return }
        let base = tinted(original, hue: hue(theme))
        let size = base.size
        NSApp.applicationIconImage = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            guard connected else { return true }
            let d = size.width * 0.26, dot = NSRect(x: rect.maxX - d - size.width * 0.08, y: rect.minY + size.width * 0.08, width: d, height: d)
            NSColor.black.withAlphaComponent(0.55).setFill(); NSBezierPath(ovalIn: dot.insetBy(dx: -d * 0.12, dy: -d * 0.12)).fill()
            NSColor.systemGreen.setFill(); NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }

    private static func tinted(_ image: NSImage, hue: Double) -> NSImage {
        guard hue != 0, let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIHueAdjust") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(hue, forKey: kCIInputAngleKey)
        guard let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }

    /// Template (adapts to the menu bar) when off, coloured shield in the theme colour when connected.
    static func menuIcon(connected: Bool, theme: ButtonTheme) -> NSImage {
        let name = connected ? "shield.lefthalf.filled" : "shield.slash"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return NSImage() }
        guard connected, let coloured = symbol.withSymbolConfiguration(.init(paletteColors: [NSColor(theme.accent)])) else {
            symbol.isTemplate = true
            return symbol
        }
        coloured.isTemplate = false
        return coloured
    }
}
#endif
