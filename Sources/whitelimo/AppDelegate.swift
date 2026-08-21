import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon and no menu bar of its own: whitelimo lives in the status
        // bar only.
        NSApp.setActivationPolicy(.accessory)

        var warnings: [String] = []
        let model = AppModel { warnings.append($0) }
        let controller = MenuBarController(model: model)
        self.model = model
        self.controller = controller

        for warning in warnings {
            Dialogs.warning(AppModel.name, warning)
        }

        // Nothing can be controlled without a token, so ask for one straight
        // away on the first run.
        if !model.configuration.isConfigured {
            controller.setToken(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutDown()
    }
}
