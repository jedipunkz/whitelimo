import XCTest
@testable import MenuKit
@testable import RemoKit

final class MenuBuilderTests: XCTestCase {
    private func build(_ json: String) throws -> MenuTree {
        let appliances = try JSONDecoder().decode([Appliance].self, from: Data(json.utf8))
        return MenuBuilder.build(from: appliances)
    }

    func testEveryControllableApplianceGetsAnEntry() throws {
        let tree = try build(Fixtures.appliances)

        XCTAssertEqual(tree.appliances.count, 4)
        XCTAssertTrue(tree.skipped.isEmpty)
        XCTAssertEqual(
            tree.appliances.map(\.nickname),
            ["Living Room AC [Air Conditioner]", "Bedroom Light [Light]", "TV [TV]", "Curtain [Remote]"]
        )
    }

    func testAnAirConditionerOffersPowerAndTheRangesOfItsCurrentMode() throws {
        let tree = try build(Fixtures.appliances)
        let aircon = try XCTUnwrap(tree.appliances.first)

        XCTAssertEqual(aircon.actions.map(\.label), ["Turn On", "Turn Off"])
        XCTAssertEqual(aircon.actions.map(\.value), ["", "power-off"])
        XCTAssertEqual(aircon.actions.map(\.kind), [.airconPower, .airconPower])

        XCTAssertEqual(aircon.groups.map(\.label), ["Mode", "Temperature (Cool)", "Fan Speed"])

        // The known modes come first, in the order the Nature app uses.
        XCTAssertEqual(aircon.groups[0].actions.map(\.label), ["Cool", "Heat", "Auto"])
        XCTAssertEqual(aircon.groups[0].actions.map(\.value), ["cool", "warm", "auto"])

        // The unit comes from the appliance, and the range from the mode the
        // air conditioner is currently in.
        XCTAssertEqual(aircon.groups[1].actions.map(\.label), ["25 °C", "26 °C", "27 °C"])
        XCTAssertEqual(aircon.groups[1].actions.map(\.kind), [.airconTemperature, .airconTemperature, .airconTemperature])

        XCTAssertEqual(aircon.groups[2].actions.map(\.label), ["1", "2", "Auto"])
        XCTAssertEqual(aircon.groups[2].actions.map(\.value), ["1", "2", "auto"])
    }

    func testARelativeTemperatureRangeIsLabelledAsAnOffset() throws {
        let tree = try build(Fixtures.airconInAutoMode)
        let aircon = try XCTUnwrap(tree.appliances.first)

        let temperatures = try XCTUnwrap(aircon.groups.first { $0.label.hasPrefix("Adjust Temperature") })
        XCTAssertEqual(temperatures.label, "Adjust Temperature (Auto)")
        XCTAssertEqual(temperatures.actions.map(\.label), ["-1", "-0.5", "±0", "+0.5", "+1"])
        // The value sent to the API is always the one the range reported.
        XCTAssertEqual(temperatures.actions.map(\.value), ["-1", "-0.5", "0", "0.5", "1"])

        // An empty fan speed is the automatic one.
        let volumes = try XCTUnwrap(aircon.groups.first { $0.label == "Fan Speed" })
        XCTAssertEqual(volumes.actions.map(\.label), ["Auto"])
        XCTAssertEqual(volumes.actions.map(\.value), [""])
    }

    func testButtonsBecomeActionsAndFallBackToTheirName() throws {
        let tree = try build(Fixtures.appliances)

        let light = tree.appliances[1]
        XCTAssertEqual(light.actions.map(\.label), ["On", "off"])
        XCTAssertEqual(light.actions.map(\.kind), [.light, .light])
        XCTAssertEqual(light.actions.map(\.value), ["on", "off"])

        let tv = tree.appliances[2]
        XCTAssertEqual(tv.actions.map(\.label), ["Power", "Terrestrial"])
        XCTAssertEqual(tv.actions.map(\.kind), [.tv, .tv])
    }

    func testLearnedSignalsFallBackToTheirIdentifier() throws {
        let tree = try build(Fixtures.appliances)
        let curtain = tree.appliances[3]

        XCTAssertEqual(curtain.actions.map(\.label), ["Open", "signal-2"])
        XCTAssertEqual(curtain.actions.map(\.kind), [.signal, .signal])
        XCTAssertEqual(curtain.actions.map(\.value), ["signal-1", "signal-2"])
    }

    func testAnApplianceWithNothingToClickIsReportedAsSkipped() throws {
        let tree = try build(Fixtures.unsupportedOnly)

        XCTAssertTrue(tree.appliances.isEmpty)
        XCTAssertEqual(tree.skipped.count, 1)
        XCTAssertEqual(tree.skipped[0].summary, "Smart Meter (EL_SMART_METER)")
    }

    func testAnAirConditionerWithoutRangesStillTurnsOnAndOff() throws {
        let tree = try build(Fixtures.sparse)

        let aircon = tree.appliances[0]
        // A blank nickname falls back to the model name.
        XCTAssertEqual(aircon.nickname, "Nameless AC [Air Conditioner]")
        XCTAssertEqual(aircon.actions.map(\.label), ["Turn On", "Turn Off"])
        XCTAssertTrue(aircon.groups.isEmpty)

        // An unknown appliance type keeps whatever signals it carries.
        let gadget = tree.appliances[1]
        XCTAssertEqual(gadget.nickname, "Gadget")
        XCTAssertEqual(gadget.actions.map(\.value), ["signal-9"])
    }

    func testTheTreeSurvivesARoundTripThroughJSON() throws {
        let tree = try build(Fixtures.appliances)

        let data = try JSONEncoder().encode(tree)
        let restored = try JSONDecoder().decode(MenuTree.self, from: data)

        XCTAssertEqual(tree, restored)
    }

    func testUnknownModesAreListedAfterTheKnownOnesInAlphabeticalOrder() {
        let ranges: [String: AirconModeRange] = [
            "zephyr": AirconModeRange(),
            "cool": AirconModeRange(),
            "boost": AirconModeRange(),
            "auto": AirconModeRange(),
        ]
        XCTAssertEqual(MenuBuilder.sortedModes(ranges), ["cool", "auto", "boost", "zephyr"])
    }

    func testOnlyARangeThatCannotBeAbsoluteCountsAsAnOffsetRange() {
        XCTAssertTrue(MenuBuilder.looksLikeOffsets(["-2", "0", "2"]))
        XCTAssertTrue(MenuBuilder.looksLikeOffsets(["+1", "+2"]))
        XCTAssertFalse(MenuBuilder.looksLikeOffsets(["16", "17", "18"]))
        XCTAssertFalse(MenuBuilder.looksLikeOffsets([]))
        XCTAssertFalse(MenuBuilder.looksLikeOffsets([""]))
    }
}
