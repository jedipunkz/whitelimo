import Foundation

/// Payloads shaped like the ones `GET /1/appliances` returns, trimmed to the
/// fields whitelimo reads.
enum Fixtures {
    static let appliances = """
    [
      {
        "id": "aircon-1",
        "type": "AC",
        "nickname": "Living Room AC",
        "device": { "id": "device-1", "name": "Remo" },
        "model": { "id": "model-1", "manufacturer": "daikin", "name": "Daikin AC" },
        "settings": {
          "temp": "26",
          "temp_unit": "c",
          "mode": "cool",
          "vol": "auto",
          "dir": "auto",
          "dirh": "auto",
          "button": "",
          "updated_at": "2026-08-01T12:00:00Z"
        },
        "aircon": {
          "tempUnit": "c",
          "range": {
            "modes": {
              "cool": { "temp": ["25", "26", "27"], "vol": ["1", "2", "auto"], "dir": [""], "dirh": [""] },
              "warm": { "temp": ["20", "21"], "vol": ["auto"], "dir": [""], "dirh": [""] },
              "auto": { "temp": ["-1", "0", "1"], "vol": ["auto"], "dir": [""], "dirh": [""] }
            },
            "fixedButtons": ["power-off"]
          }
        },
        "signals": []
      },
      {
        "id": "light-1",
        "type": "LIGHT",
        "nickname": "Bedroom Light",
        "light": {
          "state": { "brightness": "8", "power": "on", "last_button": "on" },
          "buttons": [
            { "name": "on", "image": "ico_on", "label": "On" },
            { "name": "off", "image": "ico_off", "label": "" }
          ]
        },
        "signals": []
      },
      {
        "id": "tv-1",
        "type": "TV",
        "nickname": "TV",
        "tv": {
          "state": { "input": "t" },
          "buttons": [
            { "name": "power", "image": "ico_power", "label": "Power" },
            { "name": "input-t", "image": "ico_t", "label": "Terrestrial" }
          ]
        },
        "signals": []
      },
      {
        "id": "ir-1",
        "type": "IR",
        "nickname": "Curtain",
        "signals": [
          { "id": "signal-1", "name": "Open", "image": "ico_arrow_top" },
          { "id": "signal-2", "name": "", "image": "ico_arrow_bottom" }
        ]
      }
    ]
    """

    /// An account whose only appliance is one whitelimo cannot control.
    static let unsupportedOnly = """
    [
      { "id": "meter-1", "type": "EL_SMART_METER", "nickname": "Smart Meter", "signals": [] }
    ]
    """
}

extension Fixtures {
    /// The same air conditioner, but sitting in the automatic mode, where the
    /// API reports temperatures as offsets from the room temperature.
    static let airconInAutoMode = """
    [
      {
        "id": "aircon-2",
        "type": "AC",
        "nickname": "Study AC",
        "settings": { "temp": "0", "temp_unit": "c", "mode": "auto", "vol": "", "button": "" },
        "aircon": {
          "tempUnit": "c",
          "range": {
            "modes": {
              "cool": { "temp": ["25", "26"], "vol": ["1"] },
              "auto": { "temp": ["-1", "-0.5", "0", "0.5", "1"], "vol": [""] }
            }
          }
        }
      }
    ]
    """

    /// An air conditioner the API describes without any capability range, and an
    /// appliance of a type whitelimo does not know that still carries a signal.
    static let sparse = """
    [
      { "id": "aircon-3", "type": "AC", "nickname": "  ", "model": { "name": "Nameless AC" } },
      {
        "id": "unknown-1",
        "type": "SOMETHING_NEW",
        "nickname": "Gadget",
        "signals": [{ "id": "signal-9", "name": "Toggle" }]
      }
    ]
    """
}
