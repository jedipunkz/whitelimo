import Foundation
import RemoKit

/// Performs the API call a menu entry stands for.
public enum MenuExecutor {
    /// Runs `action` and returns a short description of the resulting state,
    /// suitable for the status line at the top of the menu. The description is
    /// empty when the API returns nothing interesting.
    @discardableResult
    public static func execute(_ action: MenuAction, using client: RemoClient) async throws -> String {
        switch action.kind {
        case .signal:
            try await client.sendSignal(id: action.value)
            return ""

        case .light:
            let state = try await client.sendLightButton(
                applianceID: action.applianceID,
                button: action.value
            )
            return summary(of: state)

        case .tv:
            let state = try await client.sendTVButton(
                applianceID: action.applianceID,
                button: action.value
            )
            return summary(of: state)

        case .airconPower:
            let settings = try await client.updateAirconSettings(
                applianceID: action.applianceID,
                parameters: AirconParameters(button: action.value)
            )
            return summary(of: settings)

        case .airconMode:
            // The empty button turns the unit on. Changing a setting on an air
            // conditioner that is off would otherwise emit a signal that keeps
            // it off, which is not what picking a mode from the menu is asking
            // for — and turning it on is what the Nature app does too.
            let settings = try await client.updateAirconSettings(
                applianceID: action.applianceID,
                parameters: AirconParameters(operationMode: action.value, button: "")
            )
            return summary(of: settings)

        case .airconTemperature:
            let settings = try await client.updateAirconSettings(
                applianceID: action.applianceID,
                parameters: AirconParameters(temperature: action.value, button: "")
            )
            return summary(of: settings)

        case .airconVolume:
            let settings = try await client.updateAirconSettings(
                applianceID: action.applianceID,
                parameters: AirconParameters(airVolume: action.value, button: "")
            )
            return summary(of: settings)
        }
    }

    /// The three tuner inputs the API reports for a TV.
    static let tvInputLabels: [String: String] = [
        "t": "Terrestrial",
        "bs": "BS",
        "cs": "CS",
    ]

    static func summary(of state: TVState) -> String {
        guard let input = state.input, !input.isEmpty else { return "" }
        return "Input " + (tvInputLabels[input] ?? input)
    }

    static func summary(of state: LightState) -> String {
        guard let power = state.power, !power.isEmpty else { return "" }
        switch power {
        case "on": return "On"
        case "off": return "Off"
        default: return power
        }
    }

    /// Describes the settings the API echoed back. Every field is optional in
    /// practice, so the parts are joined rather than formatted into a fixed
    /// template that would leave stray spaces behind.
    static func summary(of settings: AirconSettings) -> String {
        if settings.button == "power-off" {
            return "Off"
        }
        var parts: [String] = []
        if let mode = settings.mode, !mode.isEmpty {
            parts.append(MenuBuilder.label(forMode: mode))
        }
        if let temperature = settings.temperature, !temperature.isEmpty {
            parts.append(self.temperature(temperature, unit: settings.temperatureUnit))
        }
        return parts.joined(separator: " ")
    }

    /// Renders a single temperature echoed back by the API. The unit is only
    /// shown when the API said what it was, and never for a value that can only
    /// be relative.
    ///
    /// Unlike the menu, which sees the whole range of a mode, this only ever
    /// sees one number: a positive value in a relative mode is indistinguishable
    /// from an absolute temperature and is printed with the unit. That only
    /// affects the wording of the status line — the value sent to the air
    /// conditioner is always the one the range reported.
    static func temperature(_ value: String, unit: String?) -> String {
        if MenuBuilder.looksLikeOffsets([value]) {
            return MenuBuilder.offsetLabel(value)
        }
        switch unit?.lowercased() {
        case "c": return value + "°C"
        case "f": return value + "°F"
        default: return value
        }
    }
}
