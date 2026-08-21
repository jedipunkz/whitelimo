import AppKit

/// The entry point.
///
/// `main` is main-actor isolated because everything whitelimo does — the status
/// item, the menu, the alerts — is AppKit, and AppKit belongs to the main
/// thread.
@main
enum WhiteLimoApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // Set here as well as in the delegate, so no Dock icon ever flashes up
        // before the application finishes launching.
        application.setActivationPolicy(.accessory)
        application.run()
        // Keeps the delegate alive for the whole run loop: NSApplication does
        // not hold a strong reference to it.
        withExtendedLifetime(delegate) {}
    }
}
