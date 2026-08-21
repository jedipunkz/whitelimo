import XCTest
@testable import WhiteLimoCore

final class AppLogTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("whitelimo-log-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var logURL: URL {
        directory.appendingPathComponent("whitelimo.log", isDirectory: false)
    }

    func testLinesAreAppendedToTheFile() throws {
        let log = AppLog(url: logURL)
        log.write("first")
        log.write("second")
        log.close()

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(" first"), contents)
        XCTAssertTrue(lines[1].hasSuffix(" second"), contents)
    }

    func testAnExistingLogIsContinued() throws {
        let first = AppLog(url: logURL)
        first.write("before")
        first.close()

        let second = AppLog(url: logURL)
        second.write("after")
        second.close()

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("before"), contents)
        XCTAssertTrue(contents.contains("after"), contents)
    }

    func testAnOversizedLogIsStartedOver() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oversized = Data(repeating: 0x61, count: Int(AppLog.maximumSize) + 1)
        try oversized.write(to: logURL)

        let log = AppLog(url: logURL)
        log.write("fresh start")
        log.close()

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.hasSuffix("fresh start\n"), String(contents.prefix(80)))
        XCTAssertLessThan(contents.count, 100)
    }

    func testALogThatCannotBeOpenedDropsItsMessages() {
        // A path whose parent is a file, not a folder: nothing can be created
        // there, and that must not be fatal.
        let log = AppLog(url: URL(fileURLWithPath: "/dev/null/whitelimo.log"))
        log.write("dropped")
        log.close()

        XCTAssertNil(log.url)
    }
}
