import XCTest
@testable import KlodikCore

final class ListFilterTests: XCTestCase {
    func item(_ title: String, _ project: String) -> TrackedItem {
        TrackedItem(localId: title, cliSessionId: nil, title: title, projectName: project, dot: .blue,
                    waitingSince: Date(), openedSinceWaiting: false, detail: nil)
    }

    lazy var items = [item("🚚 Lamoda — Поставки", "RAY-lamoda-templates"), item("📣 Lamoda — Реклама", "RAY-lamoda-templates"),
                      item("Краски · главная", "kraski-marketplace"), item("сметы", "remont-kras96")]

    func testQueryMatchesTitleOrProjectAnyCase() {
        XCTAssertEqual(ListFilter.apply(items, query: "ламода", project: nil).count, 2)              // латиницей
        XCTAssertEqual(ListFilter.apply(items, query: "рекл", project: nil).map(\.title), ["📣 Lamoda — Реклама"])
        XCTAssertEqual(ListFilter.apply(items, query: "LAMODA", project: nil).count, 2)
        XCTAssertEqual(ListFilter.apply(items, query: "краски", project: nil).map(\.title), ["Краски · главная"])
        XCTAssertEqual(ListFilter.apply(items, query: "kras", project: nil).count, 2)        // и kraski, и remont-kras96
        XCTAssertEqual(ListFilter.apply(items, query: "lamoda рекл", project: nil).map(\.title), ["📣 Lamoda — Реклама"])
        XCTAssertEqual(ListFilter.apply(items, query: "  ", project: nil).count, 4)
    }

    func testProjectFilterAndButtons() {
        XCTAssertEqual(ListFilter.apply(items, query: "", project: "kraski-marketplace").count, 1)
        XCTAssertEqual(ListFilter.apply(items, query: "сметы", project: "kraski-marketplace").count, 0)
        XCTAssertEqual(ListFilter.projects(items).map(\.name), ["RAY-lamoda-templates", "kraski-marketplace", "remont-kras96"])
        XCTAssertEqual(ListFilter.projects(items).first?.count, 2)
    }
}
