import XCTest
@testable import RemoKit

final class RemoClientTests: XCTestCase {
    let baseURL = URL(string: "https://api.example.test")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func client(token: String = "token") -> RemoClient {
        RemoClient(token: token, baseURL: baseURL, session: StubURLProtocol.session())
    }

    func testMeReturnsTheAccountOwner() async throws {
        StubURLProtocol.handler = { _ in
            .json(#"{"id":"abc","nickname":"jedipunkz"}"#)
        }

        let user = try await client().me()

        XCTAssertEqual(user.nickname, "jedipunkz")
        XCTAssertEqual(StubURLProtocol.recorded.count, 1)
        let request = StubURLProtocol.recorded[0].request
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.test/1/users/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testAppliancesDecodesEveryApplianceShape() async throws {
        StubURLProtocol.handler = { _ in .json(Fixtures.appliances) }

        let appliances = try await client().appliances()

        XCTAssertEqual(appliances.count, 4)

        let aircon = appliances[0]
        XCTAssertEqual(aircon.type, ApplianceType.airConditioner)
        XCTAssertEqual(aircon.nickname, "Living Room AC")
        XCTAssertEqual(aircon.settings?.mode, "cool")
        XCTAssertEqual(aircon.settings?.temperature, "26")
        XCTAssertEqual(aircon.aircon?.temperatureUnit, "c")
        XCTAssertEqual(aircon.aircon?.range?.modes?["cool"]?.temperature, ["25", "26", "27"])
        XCTAssertEqual(aircon.aircon?.range?.modes?["cool"]?.volume, ["1", "2", "auto"])

        XCTAssertEqual(appliances[1].light?.buttons?.count, 2)
        XCTAssertEqual(appliances[1].light?.buttons?[0].displayName, "On")
        XCTAssertEqual(appliances[1].light?.state?.power, "on")

        XCTAssertEqual(appliances[2].tv?.buttons?.first?.name, "power")
        XCTAssertEqual(appliances[3].signals?.first?.name, "Open")
    }

    func testUnauthorizedIsReportedAsSuch() async {
        StubURLProtocol.handler = { _ in
            .json(#"{"code":401001,"message":"Unauthorized"}"#, status: 401)
        }

        do {
            _ = try await client().me()
            XCTFail("expected the call to fail")
        } catch let error as RemoError {
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertFalse(error.isRateLimited)
            XCTAssertEqual(error.localizedDescription, "Nature Remo API: 401 Unauthorized")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRateLimitIsReadFromTheHeaders() async throws {
        let reset = Date().addingTimeInterval(300)
        StubURLProtocol.handler = { _ in
            .json(
                #"{"message":"Too Many Requests"}"#,
                status: 429,
                headers: [
                    "X-Rate-Limit-Limit": "30",
                    "X-Rate-Limit-Remaining": "0",
                    "X-Rate-Limit-Reset": String(Int(reset.timeIntervalSince1970)),
                ]
            )
        }

        do {
            _ = try await client().appliances()
            XCTFail("expected the call to fail")
        } catch let error as RemoError {
            XCTAssertTrue(error.isRateLimited)
            XCTAssertEqual(error.rateLimit?.limit, 30)
            XCTAssertEqual(error.rateLimit?.remaining, 0)
            let retryAfter = try XCTUnwrap(error.rateLimit?.retryAfter)
            XCTAssertEqual(retryAfter, 300, accuracy: 5)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAnEmptyTokenNeverReachesTheNetwork() async {
        StubURLProtocol.handler = { _ in .json("{}") }

        do {
            _ = try await client(token: "").me()
            XCTFail("expected the call to fail")
        } catch let error as RemoError {
            XCTAssertEqual(error, .missingToken)
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertTrue(StubURLProtocol.recorded.isEmpty)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAirconUpdateSendsOnlyTheFieldsThatWereSet() async throws {
        StubURLProtocol.handler = { _ in
            .json(#"{"temp":"24","temp_unit":"c","mode":"cool","vol":"auto","button":""}"#)
        }

        let settings = try await client().updateAirconSettings(
            applianceID: "appliance-1",
            parameters: AirconParameters(temperature: "24", button: "")
        )

        XCTAssertEqual(settings.temperature, "24")
        XCTAssertEqual(settings.mode, "cool")

        let recorded = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(recorded.request.httpMethod, "POST")
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://api.example.test/1/appliances/appliance-1/aircon_settings"
        )
        XCTAssertEqual(
            recorded.request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        XCTAssertEqual(String(decoding: recorded.body, as: UTF8.self), "button=&temperature=24")
    }

    func testAirconUpdateWithoutAnyFieldIsRejected() async {
        do {
            _ = try await client().updateAirconSettings(
                applianceID: "appliance-1",
                parameters: AirconParameters()
            )
            XCTFail("expected the call to fail")
        } catch let error as RemoError {
            XCTAssertEqual(error, .missingIdentifier("air conditioner setting to update"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSendSignalPostsToTheSignalEndpoint() async throws {
        StubURLProtocol.handler = { _ in Stub() }

        try await client().sendSignal(id: "signal 1")

        let recorded = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(
            recorded.request.url?.absoluteString,
            "https://api.example.test/1/signals/signal%201/send"
        )
        XCTAssertEqual(recorded.request.httpMethod, "POST")
    }

    func testFormEncodingEscapesReservedCharacters() {
        XCTAssertEqual(
            RemoClient.encodeForm(["button": "power-off", "operation_mode": "cool"]),
            "button=power-off&operation_mode=cool"
        )
        XCTAssertEqual(RemoClient.encodeForm(["a": "1 & 2=3+4"]), "a=1%20%26%202%3D3%2B4")
        XCTAssertEqual(RemoClient.encodeForm([:]), "")
    }

    func testAnErrorBodyThatIsNotJSONStillProducesAMessage() {
        let html = Data("<html>\n  <body>Bad Gateway</body>\n</html>".utf8)
        XCTAssertEqual(RemoClient.message(from: html), "<html> <body>Bad Gateway</body> </html>")

        let long = Data(String(repeating: "x", count: 400).utf8)
        let message = RemoClient.message(from: long)
        XCTAssertEqual(message.count, RemoClient.maximumErrorDetail + 1)
        XCTAssertTrue(message.hasSuffix("…"))
    }

    func testAMalformedResponseIsADecodingFailure() async {
        StubURLProtocol.handler = { _ in .json("not json at all") }

        do {
            _ = try await client().me()
            XCTFail("expected the call to fail")
        } catch let error as RemoError {
            guard case .decoding = error else {
                return XCTFail("expected a decoding failure, got \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

private typealias Stub = StubURLProtocol.Stub
