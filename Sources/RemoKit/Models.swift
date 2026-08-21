import Foundation

/// The values the API uses in the `type` field of an appliance.
public enum ApplianceType {
    public static let airConditioner = "AC"
    public static let tv = "TV"
    public static let light = "LIGHT"
    public static let infrared = "IR"
}

/// The owner of an access token, as returned by `GET /1/users/me`.
public struct User: Codable, Equatable, Sendable {
    public var id: String
    public var nickname: String

    public init(id: String, nickname: String) {
        self.id = id
        self.nickname = nickname
    }
}

/// A Nature Remo device.
public struct Device: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var firmwareVersion: String?
    public var macAddress: String?
    public var serialNumber: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firmwareVersion = "firmware_version"
        case macAddress = "mac_address"
        case serialNumber = "serial_number"
    }
}

/// The model metadata of an appliance. The API returns a union of several model
/// shapes, so only the fields common to all of them are kept.
public struct ApplianceModel: Codable, Equatable, Sendable {
    public var id: String?
    public var manufacturer: String?
    public var name: String?
    public var country: String?
    public var series: String?
    public var remoteName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case manufacturer
        case name
        case country
        case series
        case remoteName = "remote_name"
    }
}

/// A learned infrared signal belonging to an appliance.
public struct Signal: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var image: String?

    public init(id: String, name: String? = nil, image: String? = nil) {
        self.id = id
        self.name = name
        self.image = image
    }
}

/// A predefined button of a TV or a light appliance.
public struct Button: Codable, Equatable, Sendable {
    public var name: String
    public var image: String?
    public var label: String?

    public init(name: String, image: String? = nil, label: String? = nil) {
        self.name = name
        self.image = image
        self.label = label
    }

    /// The label of the button, falling back to its name.
    public var displayName: String {
        if let label, !label.isEmpty {
            return label
        }
        return name
    }
}

/// The last known state of an air conditioner.
public struct AirconSettings: Codable, Equatable, Sendable {
    public var temperature: String?
    public var temperatureUnit: String?
    public var mode: String?
    public var volume: String?
    public var direction: String?
    public var horizontalDirection: String?
    public var button: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case temperature = "temp"
        case temperatureUnit = "temp_unit"
        case mode
        case volume = "vol"
        case direction = "dir"
        case horizontalDirection = "dirh"
        case button
        case updatedAt = "updated_at"
    }

    public init(
        temperature: String? = nil,
        temperatureUnit: String? = nil,
        mode: String? = nil,
        volume: String? = nil,
        direction: String? = nil,
        horizontalDirection: String? = nil,
        button: String? = nil,
        updatedAt: String? = nil
    ) {
        self.temperature = temperature
        self.temperatureUnit = temperatureUnit
        self.mode = mode
        self.volume = volume
        self.direction = direction
        self.horizontalDirection = horizontalDirection
        self.button = button
        self.updatedAt = updatedAt
    }
}

/// The set of values an air conditioner accepts in one operation mode.
public struct AirconModeRange: Codable, Equatable, Sendable {
    public var temperature: [String]?
    public var volume: [String]?
    public var direction: [String]?
    public var horizontalDirection: [String]?

    enum CodingKeys: String, CodingKey {
        case temperature = "temp"
        case volume = "vol"
        case direction = "dir"
        case horizontalDirection = "dirh"
    }
}

/// The capability description of an air conditioner.
public struct AirconRange: Codable, Equatable, Sendable {
    public var modes: [String: AirconModeRange]?
    public var fixedButtons: [String]?
}

/// The air conditioner specific part of an appliance.
public struct Aircon: Codable, Equatable, Sendable {
    public var range: AirconRange?
    public var temperatureUnit: String?

    enum CodingKeys: String, CodingKey {
        case range
        case temperatureUnit = "tempUnit"
    }
}

/// The last known state of a light appliance.
public struct LightState: Codable, Equatable, Sendable {
    public var brightness: String?
    public var power: String?
    public var lastButton: String?

    enum CodingKeys: String, CodingKey {
        case brightness
        case power
        case lastButton = "last_button"
    }

    public init(brightness: String? = nil, power: String? = nil, lastButton: String? = nil) {
        self.brightness = brightness
        self.power = power
        self.lastButton = lastButton
    }
}

/// The light specific part of an appliance.
public struct Light: Codable, Equatable, Sendable {
    public var state: LightState?
    public var buttons: [Button]?
}

/// The last known state of a TV appliance.
public struct TVState: Codable, Equatable, Sendable {
    public var input: String?

    public init(input: String? = nil) {
        self.input = input
    }
}

/// The TV specific part of an appliance.
public struct TV: Codable, Equatable, Sendable {
    public var state: TVState?
    public var buttons: [Button]?
}

/// One entry of `GET /1/appliances`.
public struct Appliance: Codable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var nickname: String?
    public var image: String?
    public var device: Device?
    public var model: ApplianceModel?
    public var settings: AirconSettings?
    public var aircon: Aircon?
    public var tv: TV?
    public var light: Light?
    public var signals: [Signal]?
}

/// An update of the air conditioner settings. Only the non-nil fields are sent,
/// and the Nature API merges them into the current settings of the appliance.
public struct AirconParameters: Equatable, Sendable {
    public var temperature: String?
    public var operationMode: String?
    public var airVolume: String?
    public var airDirection: String?
    /// `"power-off"` turns the air conditioner off and `""` turns it on, so an
    /// empty string is meaningful and nil means "leave the power alone".
    public var button: String?

    public init(
        temperature: String? = nil,
        operationMode: String? = nil,
        airVolume: String? = nil,
        airDirection: String? = nil,
        button: String? = nil
    ) {
        self.temperature = temperature
        self.operationMode = operationMode
        self.airVolume = airVolume
        self.airDirection = airDirection
        self.button = button
    }

    /// The form fields this update sends.
    public var formFields: [String: String] {
        var form: [String: String] = [:]
        if let temperature { form["temperature"] = temperature }
        if let operationMode { form["operation_mode"] = operationMode }
        if let airVolume { form["air_volume"] = airVolume }
        if let airDirection { form["air_direction"] = airDirection }
        if let button { form["button"] = button }
        return form
    }
}
