import XCTest
@testable import KlodikCore

final class ClaudeUnreadTests: XCTestCase {
    let key = ClaudeUnread.key

    // MARK: Сборка файлов LevelDB для тестов

    func varint(_ v: Int) -> [UInt8] {
        var v = v, out: [UInt8] = []
        while v >= 0x80 { out.append(UInt8(v & 0x7f | 0x80)); v >>= 7 }
        return out + [UInt8(v)]
    }

    func le(_ v: UInt64, _ n: Int) -> [UInt8] { (0..<n).map { UInt8(v >> (8 * UInt64($0)) & 0xff) } }

    func internalKey(_ user: [UInt8], seq: UInt64, put: Bool = true) -> [UInt8] {
        user + le(seq << 8 | (put ? 1 : 0), 8)
    }

    /// Блок без сжатия общего префикса: у каждой записи своя точка перезапуска не нужна, одной хватает.
    func block(_ entries: [([UInt8], [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        for (k, v) in entries { out += varint(0) + varint(k.count) + varint(v.count) + k + v }
        return out + le(0, 4) + le(1, 4)
    }

    /// Таблица: блоки данных, индекс и подвал. `compress` — блоки данных одним литералом snappy.
    func table(_ blocks: [[([UInt8], [UInt8])]], compress: Bool = false) -> Data {
        var file: [UInt8] = []
        var index: [([UInt8], [UInt8])] = []
        for entries in blocks {
            var raw = block(entries)
            if compress { raw = varint(raw.count) + literal(raw) }
            index.append((entries.last!.0, varint(file.count) + varint(raw.count)))
            file += raw + [compress ? 1 : 0] + le(0, 4)
        }
        let indexRaw = block(index)
        let indexHandle = varint(file.count) + varint(indexRaw.count)
        file += indexRaw + [0] + le(0, 4)
        var footer = varint(0) + varint(0) + indexHandle
        footer += [UInt8](repeating: 0, count: 40 - footer.count)
        footer += [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb]
        return Data(file + footer)
    }

    func literal(_ bytes: [UInt8]) -> [UInt8] {
        bytes.count <= 60 ? [UInt8((bytes.count - 1) << 2)] + bytes : [60 << 2, UInt8(bytes.count - 1)] + bytes
    }

    func log(_ batches: [(seq: UInt64, ops: [([UInt8], [UInt8]?)])]) -> [UInt8] {
        var out: [UInt8] = []
        for b in batches {
            var payload = le(b.seq, 8) + le(UInt64(b.ops.count), 4)
            for (k, v) in b.ops {
                payload += [v == nil ? 0 : 1] + varint(k.count) + k
                if let v { payload += varint(v.count) + v }
            }
            out += le(0, 4) + le(UInt64(payload.count), 2) + [1] + payload
        }
        return out
    }

    func value(_ json: String) -> [UInt8] { [1] + Array(json.utf8) }

    // MARK: LevelDB

    func testSnappyLiteralsAndCopies() {
        // «abcd», затем копия 8 байт с расстояния 4 (перекрытие) и копия 2 байта двухбайтовым смещением.
        let input: [UInt8] = varint(14) + [3 << 2] + Array("abcd".utf8) + [UInt8((8 - 4) << 2 | 1), 4] + [UInt8((2 - 1) << 2 | 2), 6, 0]
        XCTAssertEqual(LevelDB.snappy(input).map { String(decoding: $0, as: UTF8.self) }, "abcdabcdabcdcd")
    }

    func testSnappyRejectsGarbage() {
        XCTAssertNil(LevelDB.snappy(varint(10) + [UInt8(4 << 2 | 1), 9]))   // ссылка назад дальше начала
        XCTAssertNil(LevelDB.snappy(varint(10) + [3 << 2, 0x61]))            // литерал длиннее входа
        XCTAssertNil(LevelDB.snappy(varint(5) + [0 << 2, 0x61]))             // длина не сошлась
    }

    func testTableFindsKeyAndNewestSequence() {
        let data = table([
            [(internalKey(Array("_a".utf8), seq: 1), [1])],
            [(internalKey(key, seq: 9), [9]), (internalKey(key, seq: 5), [5]), (internalKey(Array("_z".utf8), seq: 2), [2])],
        ], compress: true)
        XCTAssertEqual(LevelDB.lookup(table: data, key: key), .some(LevelDB.Entry(seq: 9, value: [9])))
    }

    func testTableWithoutKeyAndBrokenTable() {
        let data = table([[(internalKey(Array("_a".utf8), seq: 1), [1])]])
        XCTAssertEqual(LevelDB.lookup(table: data, key: key), .some(nil))
        var broken = [UInt8](data)
        broken[broken.count - 1] = 0
        XCTAssertNil(LevelDB.lookup(table: Data(broken), key: key))
        XCTAssertNil(LevelDB.lookup(table: Data([1, 2, 3]), key: key))
    }

    func testTableDeletion() {
        let data = table([[(internalKey(key, seq: 4, put: false), [])]])
        XCTAssertEqual(LevelDB.lookup(table: data, key: key), .some(LevelDB.Entry(seq: 4, value: nil)))
    }

    func testLogTakesLastWriteAndSurvivesTornTail() {
        var bytes = log([
            (seq: 10, ops: [(Array("_x".utf8), [0]), (key, [1])]),
            (seq: 12, ops: [(key, [2])]),
        ])
        XCTAssertEqual(LevelDB.lookup(log: bytes, key: key), LevelDB.Entry(seq: 12, value: [2]))
        // Приложение дописывает следующую запись прямо сейчас: обрывок в конце не мешает.
        bytes += le(0, 4) + le(500, 2) + [1] + [7, 7, 7]
        XCTAssertEqual(LevelDB.lookup(log: bytes, key: key), LevelDB.Entry(seq: 12, value: [2]))
    }

    // MARK: ClaudeUnread

    func testParseValue() {
        XCTAssertEqual(ClaudeUnread.parse(value(#"{"state":{"unreadIds":["local_1","local_2"],"explicitUnreadIds":["local_2"]},"version":0}"#)),
                       ["local_2"])
        XCTAssertEqual(ClaudeUnread.parse(value(#"{"state":{"unreadIds":[]},"version":0}"#)), [])
        let utf16 = [UInt8(0)] + Array(#"{"state":{"explicitUnreadIds":["local_3"]}}"#.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        XCTAssertEqual(ClaudeUnread.parse(utf16), ["local_3"])
    }

    func testParseUnknownFormatIsNil() {
        XCTAssertNil(ClaudeUnread.parse(value(#"{"unread":["local_1"]}"#)))
        XCTAssertNil(ClaudeUnread.parse(value(#"{"state":{"explicitUnreadIds":"local_1"}}"#)))
        XCTAssertNil(ClaudeUnread.parse(value("не json")))
        XCTAssertNil(ClaudeUnread.parse([7, 0x7b, 0x7d]))
        XCTAssertNil(ClaudeUnread.parse([]))
    }

    func testReadFolderPrefersNewestAcrossFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("klodik-unread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = value(#"{"state":{"explicitUnreadIds":["local_old"]}}"#)
        let new = value(#"{"state":{"explicitUnreadIds":["local_new"]}}"#)
        try table([[(internalKey(key, seq: 3), old)]]).write(to: dir.appendingPathComponent("000005.ldb"))
        try Data(log([(seq: 8, ops: [(key, new)])])).write(to: dir.appendingPathComponent("000007.log"))
        try Data("MANIFEST".utf8).write(to: dir.appendingPathComponent("MANIFEST-000001"))

        let unread = ClaudeUnread(root: dir)
        XCTAssertEqual(unread.read(), ["local_new"])

        // Журнал дописали: снята отметка (новая запись с большим номером).
        try Data(log([(seq: 8, ops: [(key, new)]), (seq: 9, ops: [(key, value(#"{"state":{"explicitUnreadIds":[]}}"#))])]))
            .write(to: dir.appendingPathComponent("000007.log"))
        XCTAssertEqual(unread.read(), [])

        // Таблица испорчена — пометок нет совсем, а не старые.
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("000009.ldb"))
        XCTAssertNil(unread.read())
    }

    func testMissingFolderIsNil() {
        XCTAssertNil(ClaudeUnread(root: URL(fileURLWithPath: "/nonexistent/klodik")).read())
    }
}
