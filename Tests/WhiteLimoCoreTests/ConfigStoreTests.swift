import MenuKit
import XCTest
@testable import WhiteLimoCore

final class ConfigStoreTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whitelimo-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var configURL: URL {
        directory.appendingPathComponent("config.json", isDirectory: false)
    }

    private func sampleConfiguration() -> Configuration {
        Configuration(
            token: "secret-token",
            userNickname: "jedipunkz",
            appliances: [
                ApplianceMenu(
                    id: "aircon-1",
                    nickname: "Living Room AC [Air Conditioner]",
                    type: "AC",
                    actions: [
                        MenuAction(label: "Turn On", kind: .airconPower, applianceID: "aircon-1", value: ""),
                    ],
                    groups: [
                        MenuGroup(label: "Mode", actions: [
                            MenuAction(label: "Cool", kind: .airconMode, applianceID: "aircon-1", value: "cool"),
                        ]),
                    ]
                ),
            ],
            skipped: [SkippedAppliance(nickname: "Smart Meter", type: "EL_SMART_METER")],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testAMissingFileLoadsAsAnEmptyConfiguration() throws {
        let store = ConfigStore(url: configURL)

        let configuration = try store.load()

        XCTAssertEqual(configuration, Configuration())
        XCTAssertFalse(configuration.isConfigured)
    }

    func testSavingThenLoadingKeepsEverything() throws {
        let store = ConfigStore(url: configURL)
        let configuration = sampleConfiguration()

        try store.save(configuration)
        let restored = try store.load()

        XCTAssertEqual(restored, configuration)
        XCTAssertTrue(restored.isConfigured)
    }

    func testTheTokenIsWrittenWhereOnlyTheOwnerCanReadIt() throws {
        let store = ConfigStore(url: configURL)

        try store.save(sampleConfiguration())

        let file = try FileManager.default.attributesOfItem(atPath: configURL.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.int16Value, 0o700)
    }

    func testReplacingAWorldReadableFileStillLeavesItOwnerOnly() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)

        try ConfigStore(url: configURL).save(sampleConfiguration())

        let file = try FileManager.default.attributesOfItem(atPath: configURL.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
    }

    func testSavingTwiceReplacesTheFile() throws {
        let store = ConfigStore(url: configURL)
        try store.save(sampleConfiguration())

        var updated = sampleConfiguration()
        updated.token = "another-token"
        updated.appliances = []
        try store.save(updated)

        let restored = try store.load()
        XCTAssertEqual(restored.token, "another-token")
        XCTAssertTrue(restored.appliances.isEmpty)
    }

    func testAConfigurationFileFromAnOlderVersionStillLoads() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"token":"only-a-token"}"#.utf8).write(to: configURL)

        let configuration = try ConfigStore(url: configURL).load()

        XCTAssertEqual(configuration.token, "only-a-token")
        XCTAssertNil(configuration.userNickname)
        XCTAssertTrue(configuration.appliances.isEmpty)
        XCTAssertNil(configuration.fetchedAt)
    }

    func testABrokenConfigurationFileIsReportedRatherThanIgnored() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: configURL)

        XCTAssertThrowsError(try ConfigStore(url: configURL).load()) { error in
            guard case ConfigError.unparsable = error else {
                return XCTFail("expected an unparsable error, got \(error)")
            }
        }
    }

    func testTheEnvironmentVariableOverridesTheLocation() throws {
        let url = try ConfigStore.defaultURL(environment: [ConfigStore.environmentKey: "~/elsewhere.json"])

        XCTAssertEqual(url.path, NSHomeDirectory() + "/elsewhere.json")
    }

    func testTheDefaultLocationLivesInApplicationSupport() throws {
        let url = try ConfigStore.defaultURL(environment: [:])

        XCTAssertEqual(url.lastPathComponent, "config.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "whitelimo")
        XCTAssertTrue(url.path.contains("Application Support"), url.path)
    }
}
