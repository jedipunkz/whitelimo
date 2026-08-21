import Foundation
import RemoKit

/// Which API call a menu entry performs.
public enum ActionKind: String, Codable, Sendable {
    /// Sends a learned IR signal (`POST /1/signals/{id}/send`).
    case signal
    /// Presses a light button (`POST /1/appliances/{id}/light`).
    case light
    /// Presses a TV button (`POST /1/appliances/{id}/tv`).
    case tv
    /// Turns an air conditioner on or off.
    case airconPower = "aircon_power"
    /// Changes the operation mode of an air conditioner.
    case airconMode = "aircon_mode"
    /// Changes the target temperature of an air conditioner.
    case airconTemperature = "aircon_temp"
    /// Changes the fan speed of an air conditioner.
    case airconVolume = "aircon_volume"
}

/// A single clickable entry of the menu.
public struct MenuAction: Codable, Equatable, Sendable {
    public var label: String
    public var kind: ActionKind
    public var applianceID: String
    /// The button name, the signal id or the setting value, depending on `kind`.
    /// An empty value is meaningful for `airconPower`, where it means "on".
    public var value: String
    public var tooltip: String?

    enum CodingKeys: String, CodingKey {
        case label
        case kind
        case applianceID = "appliance_id"
        case value
        case tooltip
    }

    public init(label: String, kind: ActionKind, applianceID: String, value: String, tooltip: String? = nil) {
        self.label = label
        self.kind = kind
        self.applianceID = applianceID
        self.value = value
        self.tooltip = tooltip
    }
}

/// A nested submenu below an appliance, which keeps long lists of temperatures
/// or modes out of the way.
public struct MenuGroup: Codable, Equatable, Sendable {
    public var label: String
    public var actions: [MenuAction]

    public init(label: String, actions: [MenuAction]) {
        self.label = label
        self.actions = actions
    }
}

/// An appliance that was left out of the menu because whitelimo has no way to
/// send anything to it.
///
/// The Nature API covers far more than infrared: smart meters, smart locks, EV
/// chargers and ECHONET Lite appliances all show up in the appliance list with
/// endpoints of their own. Recording them means the user can be told why a
/// device is missing instead of wondering.
public struct SkippedAppliance: Codable, Equatable, Sendable {
    public var nickname: String
    public var type: String

    public init(nickname: String, type: String) {
        self.nickname = nickname
        self.type = type
    }

    /// Names the appliance for an alert.
    public var summary: String {
        type.isEmpty ? nickname : "\(nickname) (\(type))"
    }
}

/// One top-level entry of the menu.
public struct ApplianceMenu: Codable, Equatable, Sendable {
    public var id: String
    public var nickname: String
    public var type: String
    public var actions: [MenuAction]
    public var groups: [MenuGroup]

    public init(
        id: String,
        nickname: String,
        type: String,
        actions: [MenuAction] = [],
        groups: [MenuGroup] = []
    ) {
        self.id = id
        self.nickname = nickname
        self.type = type
        self.actions = actions
        self.groups = groups
    }

    /// Whether the appliance has nothing that can be clicked.
    public var isEmpty: Bool {
        actions.isEmpty && groups.allSatisfy { $0.actions.isEmpty }
    }
}

/// The outcome of `MenuBuilder.build(from:)`.
public struct MenuTree: Codable, Equatable, Sendable {
    /// The entries the menu is built from.
    public var appliances: [ApplianceMenu]
    /// The appliances that offer nothing to click.
    public var skipped: [SkippedAppliance]

    public init(appliances: [ApplianceMenu] = [], skipped: [SkippedAppliance] = []) {
        self.appliances = appliances
        self.skipped = skipped
    }
}

/// Turns the appliances returned by the Nature Remo Cloud API into the flat,
/// serialisable tree the menu bar menu is built from.
///
/// Keeping the tree apart from the menu itself has two benefits: it can be
/// cached in the configuration file, so the menu is ready at launch without
/// spending an API call, and it can be unit tested without AppKit.
public enum MenuBuilder {
    public static func build(from appliances: [Appliance]) -> MenuTree {
        var tree = MenuTree()
        for appliance in appliances {
            var item = ApplianceMenu(
                id: appliance.id,
                nickname: displayName(of: appliance),
                type: appliance.type
            )

            switch appliance.type {
            case ApplianceType.airConditioner:
                let (actions, groups) = airconEntries(for: appliance)
                item.actions = actions
                item.groups = groups
            case ApplianceType.light:
                item.actions = buttonActions(
                    applianceID: appliance.id,
                    kind: .light,
                    buttons: appliance.light?.buttons ?? []
                )
            case ApplianceType.tv:
                item.actions = buttonActions(
                    applianceID: appliance.id,
                    kind: .tv,
                    buttons: appliance.tv?.buttons ?? []
                )
            default:
                break
            }

            // Learned signals belong mostly to IR appliances, but an appliance
            // of any type is free to carry a few. They are always appended.
            item.actions.append(contentsOf: signalActions(for: appliance))

            if item.isEmpty {
                tree.skipped.append(
                    SkippedAppliance(nickname: plainName(of: appliance), type: appliance.type)
                )
                continue
            }
            tree.appliances.append(item)
        }
        return tree
    }

    // MARK: - Names

    static let applianceTypeLabels: [String: String] = [
        ApplianceType.airConditioner: "Air Conditioner",
        ApplianceType.tv: "TV",
        ApplianceType.light: "Light",
        ApplianceType.infrared: "Remote",
    ]

    static func displayName(of appliance: Appliance) -> String {
        let name = plainName(of: appliance)
        if let label = applianceTypeLabels[appliance.type] {
            return "\(name) [\(label)]"
        }
        return name
    }

    /// The appliance name without the type suffix, falling back to the model
    /// name and finally to a placeholder.
    static func plainName(of appliance: Appliance) -> String {
        if let nickname = appliance.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nickname.isEmpty {
            return nickname
        }
        if let model = appliance.model?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            return model
        }
        return "(unnamed)"
    }

    // MARK: - Buttons and signals

    static func buttonActions(applianceID: String, kind: ActionKind, buttons: [Button]) -> [MenuAction] {
        buttons.compactMap { button in
            guard !button.name.isEmpty else { return nil }
            return MenuAction(
                label: button.displayName,
                kind: kind,
                applianceID: applianceID,
                value: button.name,
                tooltip: button.name
            )
        }
    }

    static func signalActions(for appliance: Appliance) -> [MenuAction] {
        (appliance.signals ?? []).compactMap { signal in
            guard !signal.id.isEmpty else { return nil }
            let label = (signal.name?.isEmpty == false) ? signal.name! : signal.id
            return MenuAction(
                label: label,
                kind: .signal,
                applianceID: appliance.id,
                value: signal.id,
                tooltip: "Sends a learned IR signal"
            )
        }
    }

    // MARK: - Air conditioners

    /// The order operation modes are listed in, matching the Nature Remo mobile
    /// app. Modes the API invents later are appended in alphabetical order.
    static let airconModeOrder = ["cool", "warm", "dry", "blow", "auto"]

    static let airconModeLabels: [String: String] = [
        "cool": "Cool",
        "warm": "Heat",
        "dry": "Dry",
        "blow": "Fan",
        "auto": "Auto",
    ]

    /// Produces "Turn On"/"Turn Off" as direct entries plus submenus for the
    /// operation mode, the temperature and the fan speed. Temperatures and fan
    /// speeds depend on the operation mode, so the ranges of the mode the unit
    /// is currently in are the ones offered.
    static func airconEntries(for appliance: Appliance) -> ([MenuAction], [MenuGroup]) {
        let actions = [
            MenuAction(
                label: "Turn On",
                kind: .airconPower,
                applianceID: appliance.id,
                value: "",
                tooltip: "Starts the air conditioner"
            ),
            MenuAction(
                label: "Turn Off",
                kind: .airconPower,
                applianceID: appliance.id,
                value: "power-off",
                tooltip: "Stops the air conditioner"
            ),
        ]

        guard let ranges = appliance.aircon?.range?.modes, !ranges.isEmpty else {
            return (actions, [])
        }

        let modes = sortedModes(ranges)
        var groups: [MenuGroup] = []

        groups.append(MenuGroup(label: "Mode", actions: modes.map { mode in
            MenuAction(
                label: label(forMode: mode),
                kind: .airconMode,
                applianceID: appliance.id,
                value: mode,
                tooltip: mode
            )
        }))

        let mode = currentMode(of: appliance, among: modes, ranges: ranges)
        let range = ranges[mode]

        let temperatures = temperatureGroup(
            for: appliance,
            mode: mode,
            values: range?.temperature ?? []
        )
        if !temperatures.actions.isEmpty {
            groups.append(temperatures)
        }

        let volumes = (range?.volume ?? []).map { volume in
            MenuAction(
                label: label(forVolume: volume),
                kind: .airconVolume,
                applianceID: appliance.id,
                value: volume
            )
        }
        if !volumes.isEmpty {
            groups.append(MenuGroup(label: "Fan Speed", actions: volumes))
        }

        return (actions, groups)
    }

    /// Turns the temperature range of one operation mode into a submenu.
    ///
    /// The values are not always absolute temperatures: in the automatic mode
    /// (and on some units the dry mode) an air conditioner expresses its setting
    /// as an offset from the room temperature, and the API reports that as a
    /// range such as -2, -1.5, … 2. Labelling those "-1.5 °C" would be nonsense,
    /// so an offset range is detected and rendered as an offset instead.
    static func temperatureGroup(for appliance: Appliance, mode: String, values: [String]) -> MenuGroup {
        let offsets = looksLikeOffsets(values)
        let modeName = label(forMode: mode)
        let groupLabel = offsets
            ? "Adjust Temperature (\(modeName))"
            : "Temperature (\(modeName))"

        let unit = temperatureUnit(of: appliance)
        let actions = values.compactMap { value -> MenuAction? in
            guard !value.isEmpty else { return nil }
            return MenuAction(
                label: temperatureLabel(value, unit: unit, offset: offsets),
                kind: .airconTemperature,
                applianceID: appliance.id,
                value: value
            )
        }
        return MenuGroup(label: groupLabel, actions: actions)
    }

    /// The unit to print after a temperature. The API uses "c", "f" or nothing
    /// at all, and nothing is printed for the last one rather than guessing.
    static func temperatureUnit(of appliance: Appliance) -> String {
        switch appliance.aircon?.temperatureUnit?.lowercased() {
        case "c": return "C"
        case "f": return "F"
        default: return ""
        }
    }

    static func temperatureLabel(_ value: String, unit: String, offset: Bool) -> String {
        if offset {
            return offsetLabel(value)
        }
        return unit.isEmpty ? value : "\(value) °\(unit)"
    }

    /// Signs a relative temperature so the direction is obvious in the menu:
    /// -2, ±0, +1.5.
    static func offsetLabel(_ value: String) -> String {
        guard let number = Double(value) else { return value }
        if number > 0 {
            return "+" + value
        }
        if number == 0 {
            return "±" + (value.hasPrefix("-") ? String(value.dropFirst()) : value)
        }
        return value
    }

    /// Whether a temperature range is relative rather than absolute. A range
    /// that contains zero, a negative value or an explicitly signed one cannot
    /// be a list of absolute temperatures: no air conditioner offers 0 °C or
    /// 0 °F as a target.
    static func looksLikeOffsets(_ values: [String]) -> Bool {
        for value in values where !value.isEmpty {
            if value.hasPrefix("+") {
                return true
            }
            if let number = Double(value), number <= 0 {
                return true
            }
        }
        return false
    }

    /// The operation mode the air conditioner is set to, or the first supported
    /// mode when the state is unknown.
    static func currentMode(
        of appliance: Appliance,
        among modes: [String],
        ranges: [String: AirconModeRange]
    ) -> String {
        if let mode = appliance.settings?.mode, !mode.isEmpty, ranges[mode] != nil {
            return mode
        }
        return modes[0]
    }

    static func sortedModes(_ ranges: [String: AirconModeRange]) -> [String] {
        let known = airconModeOrder.filter { ranges[$0] != nil }
        let rest = ranges.keys.filter { !airconModeOrder.contains($0) }.sorted()
        return known + rest
    }

    static func label(forMode mode: String) -> String {
        airconModeLabels[mode] ?? mode
    }

    /// Renders a fan speed. The API uses an empty string for automatic, and some
    /// units report the same thing as "auto".
    static func label(forVolume volume: String) -> String {
        (volume.isEmpty || volume == "auto") ? "Auto" : volume
    }
}
