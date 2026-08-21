import AppKit
import MenuKit
import WhiteLimoCore

/// Owns the status item and rebuilds its menu from the model.
///
/// The menu is thrown away and rebuilt every time it is about to open, which
/// keeps it honest: there is no second copy of the state to keep in step with
/// the configuration.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    /// Set while an API call is in flight, so a slow network cannot queue up a
    /// dozen requests behind an impatient click.
    private var isBusy = false

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = StatusIcon.image()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild()
        updateTooltip()
    }

    // MARK: - Building the menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        menu.addItem(disabledItem(model.headerText))
        if !model.status.isEmpty {
            menu.addItem(disabledItem(model.status))
        }
        menu.addItem(.separator())

        if !model.configuration.isConfigured {
            menu.addItem(command("Set Access Token…", #selector(setToken(_:)), enabled: !isBusy))
            menu.addItem(command("Get an Access Token…", #selector(openTokenPage(_:))))
        } else if model.configuration.appliances.isEmpty {
            menu.addItem(disabledItem("No appliances fetched yet"))
        } else {
            for appliance in model.configuration.appliances {
                menu.addItem(item(for: appliance))
            }
        }

        menu.addItem(.separator())
        if model.configuration.isConfigured {
            menu.addItem(command("Refresh Appliances", #selector(refreshAppliances(_:)), enabled: !isBusy))
            menu.addItem(command("Set Access Token…", #selector(setToken(_:)), enabled: !isBusy))
        }
        if !model.configuration.skipped.isEmpty {
            menu.addItem(command(
                "Devices Without Controls: \(model.configuration.skipped.count)…",
                #selector(showSkipped(_:))
            ))
        }
        if model.configurationURL != nil {
            menu.addItem(command("Reveal Configuration in Finder", #selector(revealConfiguration(_:))))
        }
        menu.addItem(command("About \(AppModel.name)", #selector(showAbout(_:))))
        menu.addItem(.separator())

        let quitItem = command("Quit \(AppModel.name)", #selector(quit(_:)))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
    }

    private func item(for appliance: ApplianceMenu) -> NSMenuItem {
        let item = NSMenuItem(title: appliance.nickname, action: nil, keyEquivalent: "")
        item.isEnabled = true

        let submenu = NSMenu(title: appliance.nickname)
        submenu.autoenablesItems = false
        for action in appliance.actions {
            submenu.addItem(self.item(for: action))
        }
        if !appliance.actions.isEmpty, !appliance.groups.isEmpty {
            submenu.addItem(.separator())
        }
        for group in appliance.groups where !group.actions.isEmpty {
            let groupItem = NSMenuItem(title: group.label, action: nil, keyEquivalent: "")
            groupItem.isEnabled = true
            let groupMenu = NSMenu(title: group.label)
            groupMenu.autoenablesItems = false
            for action in group.actions {
                groupMenu.addItem(self.item(for: action))
            }
            groupItem.submenu = groupMenu
            submenu.addItem(groupItem)
        }

        item.submenu = submenu
        return item
    }

    private func item(for action: MenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.label, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionBox(action)
        item.toolTip = action.tooltip
        item.isEnabled = !isBusy
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A command item. The ones whose handler bails out while a call is in
    /// flight pass `enabled: !isBusy`, so they look as dead as they act.
    private func command(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    /// The menu bar tooltip. It is short by design: it is the only feedback for
    /// an action once the menu has closed.
    private func updateTooltip() {
        let text = model.status.isEmpty ? model.headerText : model.status
        statusItem.button?.toolTip = String(text.prefix(120))
    }

    private func setStatus(_ text: String) {
        model.setStatus(text)
        updateTooltip()
    }

    // MARK: - Commands

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox, !isBusy else { return }
        let action = box.action
        isBusy = true
        setStatus("\(action.label)…")
        Task {
            defer { isBusy = false }
            do {
                setStatus(try await model.perform(action))
            } catch {
                setStatus("\(action.label) failed")
                Dialogs.error(AppModel.name, describe(error))
            }
        }
    }

    @objc private func refreshAppliances(_ sender: NSMenuItem) {
        guard !isBusy else { return }
        isBusy = true
        setStatus("Refreshing…")
        Task {
            defer { isBusy = false }
            do {
                let tree = try await model.fetchAppliances()
                setStatus("\(tree.appliances.count) appliances")
            } catch {
                setStatus("Refresh failed")
                Dialogs.error(AppModel.name, describe(error))
            }
        }
    }

    @objc func setToken(_ sender: Any?) {
        guard !isBusy else { return }
        guard let token = Dialogs.askForToken(current: model.configuration.token) else { return }
        guard !token.isEmpty else {
            Dialogs.warning(AppModel.name, "The access token cannot be empty.")
            return
        }

        isBusy = true
        setStatus("Checking the token…")
        Task {
            defer { isBusy = false }
            do {
                let summary = try await model.configure(token: token)
                setStatus("Ready")
                Dialogs.information(AppModel.name, summary)
            } catch {
                setStatus("Setup failed")
                Dialogs.error(AppModel.name, describe(error))
            }
        }
    }

    @objc private func openTokenPage(_ sender: Any?) {
        NSWorkspace.shared.open(AppModel.tokenPage)
    }

    @objc private func showSkipped(_ sender: Any?) {
        let names = model.configuration.skipped.map { "• \($0.summary)" }.joined(separator: "\n")
        Dialogs.information(
            "Devices Without Controls",
            """
            whitelimo speaks infrared: air conditioners, lights, TVs and learned remotes. \
            These devices on the account are controlled another way, so they have no menu.

            \(names)
            """
        )
    }

    @objc private func revealConfiguration(_ sender: Any?) {
        guard let url = model.configurationURL else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        Dialogs.information("\(AppModel.name) \(AppModel.version)", model.aboutText)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

/// Carries a `MenuAction` through `NSMenuItem.representedObject`.
private final class ActionBox: NSObject {
    let action: MenuAction

    init(_ action: MenuAction) {
        self.action = action
    }
}
