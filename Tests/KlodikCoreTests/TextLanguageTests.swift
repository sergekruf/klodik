import XCTest
@testable import KlodikCore

final class TextLanguageTests: XCTestCase {
    func testSummariesFromRealSessions() {
        XCTAssertEqual(TextLanguage.detect("Lamoda plan: 285 ship now, 887 need cards; 3 decisions open"), .en)
        XCTAssertEqual(TextLanguage.detect("phones fixed; Telegram session awaits your answer"), .en)
        XCTAssertEqual(TextLanguage.detect("Catalog: open decisions on extra barcodes, 7 items"), .en)
        XCTAssertEqual(TextLanguage.detect("Нужен API-ключ М.Видео и выбор схемы FBO"), .ru)
        XCTAssertEqual(TextLanguage.detect("сверка с API готова; ждём решение по снимкам цен"), .ru)
        XCTAssertEqual(TextLanguage.detect("Lamoda: ждём решения по поставке, ценам и акции"), .ru)
    }

    func testNothingToRecognize() {
        XCTAssertNil(TextLanguage.detect(""))
        XCTAssertNil(TextLanguage.detect("285 / 887"))
    }
}
