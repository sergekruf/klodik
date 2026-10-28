import XCTest
@testable import KlodikCore

final class HTTPRequestTests: XCTestCase {
    func request(_ body: String, length: Int? = nil, headerName: String = "Content-Length") -> Data {
        Data("POST /event HTTP/1.1\r\nHost: 127.0.0.1:47821\r\nContent-Type: application/json\r\n\(headerName): \(length ?? body.utf8.count)\r\n\r\n\(body)".utf8)
    }

    func testCompleteRequest() {
        XCTAssertEqual(HTTPRequest.parse(request(#"{"a":1}"#)),
                       .request(method: "POST", path: "/event", body: Data(#"{"a":1}"#.utf8)))
    }

    func testHeaderNameIsCaseInsensitive() {
        XCTAssertEqual(HTTPRequest.parse(request("{}", headerName: "content-length")),
                       .request(method: "POST", path: "/event", body: Data("{}".utf8)))
    }

    func testHeadersNotFinishedYet() {
        XCTAssertEqual(HTTPRequest.parse(Data("POST /event HTTP/1.1\r\nHost: x\r\n".utf8)), .incomplete)
    }

    func testBodyNotFinishedYet() {
        let full = request(#"{"session_id":"abc"}"#)
        XCTAssertEqual(HTTPRequest.parse(full.dropLast(5)), .incomplete)
    }

    func testWorksOnASliceOfABiggerBuffer() {
        let full = Data("xx".utf8) + request("{}")
        XCTAssertEqual(HTTPRequest.parse(full.dropFirst(2)), .request(method: "POST", path: "/event", body: Data("{}".utf8)))
    }

    func testBodyOver64KBIsRejectedBeforeItArrives() {
        XCTAssertEqual(HTTPRequest.parse(request("", length: 64 * 1024 + 1)), .tooLarge)
    }

    func testGarbage() {
        XCTAssertEqual(HTTPRequest.parse(Data("hello\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(HTTPRequest.parse(request("{}", length: -1)), .invalid)
    }

    func testEndlessHeadersAreInvalid() {
        XCTAssertEqual(HTTPRequest.parse(Data(String(repeating: "a", count: 9000).utf8)), .invalid)
    }
}
