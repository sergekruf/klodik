import XCTest
@testable import KlodikCore

final class UpdateCheckTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateCheck.isNewer("0.2.0", than: "0.1.1"))
        XCTAssertTrue(UpdateCheck.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.1", than: "0.1.1"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1", than: "0.1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.1.0", than: "0.1.1"))
    }

    func testParsesGitHubLatestRelease() {
        let json = #"{"tag_name": "v0.2.0", "html_url": "https://github.com/sergekruf/klodik/releases/tag/v0.2.0", "name": "Клодик 0.2.0"}"#
        XCTAssertEqual(UpdateCheck.parse(Data(json.utf8)),
                       UpdateCheck.Release(version: "0.2.0", url: URL(string: "https://github.com/sergekruf/klodik/releases/tag/v0.2.0")!))
        XCTAssertNil(UpdateCheck.parse(Data(#"{"message": "Not Found"}"#.utf8)))
    }
}
