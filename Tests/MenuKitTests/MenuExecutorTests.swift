import XCTest
@testable import MenuKit
@testable import RemoKit

final class MenuExecutorTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.test")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func client() -> RemoClient {
        RemoClient(token: "token", baseURL: baseURL, session: StubURLProtocol.session())
    }

    private func action(_ kind: ActionKind, _ value: String, label: String = "entry") -> MenuAction {
        MenuAction(label: label, kind: kind, applianceID: "appliance-1", value: value)
    }

    func testPickingAModeAlsoTurnsTheUnitOn() async throws {
        StubURLProtocol.handler = { _ in
            .json(#"{"temp":"24","temp_unit":"c","mode":"cool","button":""}"#)
        }

        let summary = try await MenuExecutor.execute(action(.airconMode, "cool"), using: client())

        XCTAssertEqual(summary, "Cool 24°C")
        let recorded = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://api.example.test/1/appliances/appliance-1/aircon_settings"
        )
        // The empty button is what turns the air conditioner on: changing a
        // setting without it would emit a signal that keeps the unit off.
        XCTAssertEqual(String(decoding: recorded.body, as: UTF8.self), "button=&operation_mode=cool")
    }

    func testTurningTheUnitOffSendsOnlyTheButton() async throws {
        StubURLProtocol.handler = { _ in .json(#"{"button":"power-off","mode":"cool","temp":"24"}"#) }

        let summary = try await MenuExecutor.execute(action(.airconPower, "power-off"), using: client())

        XCTAssertEqual(summary, "Off")
        let recorded = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(String(decoding: recorded.body, as: UTF8.self), "button=power-off")
    }

    func testTemperatureAndVolumeCarryTheButtonToo() async throws {
        StubURLProtocol.handler = { _ in .json("{}") }

        _ = try await MenuExecutor.execute(action(.airconTemperature, "24"), using: client())
        _ = try await MenuExecutor.execute(action(.airconVolume, "auto"), using: client())

        XCTAssertEqual(
            StubURLProtocol.recorded.map { String(decoding: $0.body, as: UTF8.self) },
            ["button=&temperature=24", "air_volume=auto&button="]
        )
    }

    func testASignalReportsNoStateOfItsOwn() async throws {
        StubURLProtocol.handler = { _ in Stub() }

        let summary = try await MenuExecutor.execute(action(.signal, "signal-1"), using: client())

        XCTAssertEqual(summary, "")
        XCTAssertEqual(
            StubURLProtocol.recorded.first?.request.url?.absoluteString,
            "https://api.example.test/1/signals/signal-1/send"
        )
    }

    func testALightAndATVReportTheirNewState() async throws {
        StubURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/light") == true
                ? Stub.json(#"{"power":"on","brightness":"8"}"#)
                : Stub.json(#"{"input":"t"}"#)
        }

        let light = try await MenuExecutor.execute(action(.light, "on"), using: client())
        let tv = try await MenuExecutor.execute(action(.tv, "input-t"), using: client())

        XCTAssertEqual(light, "On")
        XCTAssertEqual(tv, "Input Terrestrial")
    }

    func testAFailureFromTheAPIIsPassedOn() async {
        StubURLProtocol.handler = { _ in .json(#"{"message":"Unauthorized"}"#, status: 401) }

        do {
            _ = try await MenuExecutor.execute(action(.light, "on"), using: client())
            XCTFail("expected the call to fail")
        } catch let error as RemoError {
            XCTAssertTrue(error.isUnauthorized)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSummariesAreShortEnoughForAMenuLine() {
        XCTAssertEqual(MenuExecutor.summary(of: LightState(power: "off")), "Off")
        XCTAssertEqual(MenuExecutor.summary(of: LightState(power: "dim")), "dim")
        XCTAssertEqual(MenuExecutor.summary(of: LightState()), "")

        XCTAssertEqual(MenuExecutor.summary(of: TVState(input: "bs")), "Input BS")
        XCTAssertEqual(MenuExecutor.summary(of: TVState(input: "hdmi1")), "Input hdmi1")
        XCTAssertEqual(MenuExecutor.summary(of: TVState()), "")

        XCTAssertEqual(
            MenuExecutor.summary(of: AirconSettings(temperature: "24", temperatureUnit: "c", mode: "warm")),
            "Heat 24°C"
        )
        // A relative setting is never printed with a unit.
        XCTAssertEqual(
            MenuExecutor.summary(of: AirconSettings(temperature: "-1", temperatureUnit: "c", mode: "auto")),
            "Auto -1"
        )
        XCTAssertEqual(
            MenuExecutor.summary(of: AirconSettings(temperature: "24", mode: "cool")),
            "Cool 24"
        )
        XCTAssertEqual(MenuExecutor.summary(of: AirconSettings()), "")
    }
}

private typealias Stub = StubURLProtocol.Stub
