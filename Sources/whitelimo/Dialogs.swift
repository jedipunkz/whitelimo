import AppKit

/// The alerts and the one text prompt whitelimo puts on screen. A menu bar app
/// has no window of its own, so these are the whole user interface besides the
/// menu.
@MainActor
enum Dialogs {
    static func information(_ title: String, _ text: String) {
        show(title, text, style: .informational)
    }

    static func warning(_ title: String, _ text: String) {
        show(title, text, style: .warning)
    }

    static func error(_ title: String, _ text: String) {
        show(title, text, style: .critical)
    }

    private static func show(_ title: String, _ text: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Asks for a Nature Remo personal access token. Returns nil when the user
    /// cancels, and the trimmed token otherwise.
    static func askForToken(current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Nature Remo Access Token"
        alert.informativeText = """
            Paste the personal access token issued at \(AppModel.tokenPage.absoluteString).

            The token is stored in the configuration file in your home folder, readable only by you.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Issue a Token…")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Access token"
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(AppModel.tokenPage)
            return nil
        default:
            return nil
        }
    }
}
