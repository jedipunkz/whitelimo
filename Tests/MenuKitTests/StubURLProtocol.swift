import Foundation
import XCTest

/// A URLProtocol that answers every request from a handler, so the client can be
/// tested without a network.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()

        static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> Stub {
            Stub(status: status, headers: headers, body: Data(text.utf8))
        }
    }

    /// Called for every request. Set it in the test, and read `recorded` after.
    static var handler: ((URLRequest) -> Stub)?
    /// Every request the stub saw, in order.
    static var recorded: [(request: URLRequest, body: Data)] = []

    static func reset() {
        handler = nil
        recorded = []
    }

    /// A session that routes everything through this protocol.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// URLSession turns `httpBody` into a stream before a protocol sees it, so
    /// the body has to be read back out of the stream.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = StubURLProtocol.handler?(request) ?? Stub()
        StubURLProtocol.recorded.append((request, StubURLProtocol.body(of: request)))

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stub.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: stub.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
