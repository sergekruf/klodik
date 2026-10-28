import XCTest
@testable import KlodikCore

final class EventServerTests: XCTestCase {
    /// Запускает приёмник на свободном порту и ждёт, пока он будет готов.
    func startServer() throws -> (EventServer, UInt16) {
        let server = EventServer(port: 0)
        let ready = expectation(description: "приёмник готов")
        var port: UInt16 = 0
        server.onState = { if case let .ready(p) = $0 { port = p; ready.fulfill() } }
        server.start()
        wait(for: [ready], timeout: 5)
        return (server, port)
    }

    func post(_ port: UInt16, path: String = EventServer.path, method: String = "POST", body: String) -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data(body.utf8) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let done = expectation(description: "ответ")
        var status = 0
        URLSession.shared.dataTask(with: request) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? -1
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        return status
    }

    func testPostedHookEventArrives() throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        let arrived = expectation(description: "событие дошло")
        server.onEvent = { event in
            XCTAssertEqual(event.sessionId, "53c48b4e")
            XCTAssertEqual(event.kind, .permissionRequest("Bash"))
            arrived.fulfill()
        }
        let status = post(port, body: #"{"session_id": "53c48b4e", "hook_event_name": "PermissionRequest", "tool_name": "Bash"}"#)
        XCTAssertEqual(status, 200)
        wait(for: [arrived], timeout: 5)
    }

    func testUnknownEventStillGets200() throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        server.onEvent = { _ in XCTFail("неизвестное событие не должно доходить") }
        XCTAssertEqual(post(port, body: #"{"session_id": "a", "hook_event_name": "PreCompact"}"#), 200)
    }

    func testOtherPathsAre404() throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        XCTAssertEqual(post(port, path: "/", method: "GET", body: ""), 404)
    }

    func testTooLargeBodyIs413() throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        XCTAssertEqual(post(port, body: String(repeating: "x", count: 70 * 1024)), 413)
    }

    func testBusyPortReportsFailure() throws {
        let (first, port) = try startServer()
        defer { first.stop() }
        let second = EventServer(port: port)
        let failed = expectation(description: "второй приёмник не смог занять порт")
        second.onState = { if case .failed = $0 { failed.fulfill() } }
        second.start()
        wait(for: [failed], timeout: 5)
        second.stop()
    }
}
