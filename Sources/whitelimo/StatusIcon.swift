import AppKit

/// The image shown in the menu bar.
@MainActor
enum StatusIcon {
    /// An SF Symbol when one is available, and a drawn fallback when it is not.
    /// Both are template images, so macOS tints them for the current menu bar
    /// appearance.
    static func image() -> NSImage {
        for name in ["thermometer.medium", "thermometer", "dot.radiowaves.left.and.right"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: AppModel.name) {
                image.isTemplate = true
                return image
            }
        }
        return drawn()
    }

    private static func drawn() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let text = "wl" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let bounds = text.size(withAttributes: attributes)
            let origin = NSPoint(
                x: rect.midX - bounds.width / 2,
                y: rect.midY - bounds.height / 2
            )
            text.draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }
}
