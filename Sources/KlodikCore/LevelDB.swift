import Foundation

/// Чтение одного ключа из чужой базы LevelDB (localStorage Chromium), только на чтение и без блокировки.
/// База живая: приложение пишет в неё, пока мы читаем, поэтому любой непонятный байт — nil, а не падение.
public enum LevelDB {
    /// Значение ключа из одного файла. `value == nil` — ключ удалён. Из всех файлов прав тот, у кого `seq` больше.
    public struct Entry: Equatable {
        public var seq: UInt64
        public var value: [UInt8]?
    }

    /// Найти ключ в таблице `.ldb`. Внешний nil — файл не разобрался; `.some(nil)` — ключа в файле нет.
    public static func lookup(table data: Data, key: [UInt8]) -> Entry?? {
        let footerSize = 48
        guard data.count >= footerSize else { return nil }
        var footer = Reader([UInt8](data.suffix(footerSize)))
        guard Array(footer.bytes.suffix(8)) == [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb],
              footer.varint() != nil, footer.varint() != nil,                      // метаиндекс не нужен
              let indexOffset = footer.varint(), let indexSize = footer.varint(),
              let index = block(data, offset: indexOffset, size: indexSize),
              let indexEntries = entries(index) else { return nil }

        // Индекс: для каждого блока ключ не меньше последнего ключа в нём. Ключ ищем в первом блоке,
        // чей индексный ключ не меньше нужного, и дальше, пока индексный ключ равен нужному.
        var found: Entry?
        for (indexKey, handle) in indexEntries {
            guard indexKey.count >= 8 else { return nil }
            let userKey = indexKey.dropLast(8)
            if userKey.lexicographicallyPrecedes(key) { continue }
            var h = Reader(handle)
            guard let offset = h.varint(), let size = h.varint(),
                  let raw = block(data, offset: offset, size: size),
                  let list = entries(raw) else { return nil }
            for (internalKey, value) in list where internalKey.count >= 8 && internalKey.dropLast(8).elementsEqual(key) {
                let tag = littleEndian(internalKey.suffix(8))
                let entry = Entry(seq: tag >> 8, value: tag & 0xff == 1 ? value : nil)
                if entry.seq >= found?.seq ?? 0 { found = entry }
            }
            if !userKey.elementsEqual(key) { break }
        }
        return .some(found)
    }

    /// Найти ключ в журнале `.log`. Недописанная последняя запись — норма (приложение пишет прямо сейчас),
    /// на ней чтение просто заканчивается.
    public static func lookup(log bytes: [UInt8], key: [UInt8]) -> Entry? {
        let blockSize = 32768
        var found: Entry?
        var pending: [UInt8] = []
        var pos = 0
        while pos + 7 <= bytes.count {
            let left = blockSize - pos % blockSize
            if left < 7 { pos += left; continue }                                   // хвост блока — нули
            let length = Int(bytes[pos + 4]) | Int(bytes[pos + 5]) << 8
            let type = bytes[pos + 6]
            let start = pos + 7
            guard type != 0, start + length <= bytes.count, length <= left - 7 else { break }
            let payload = bytes[start..<start + length]
            pos = start + length
            switch type {
            case 1: pending = Array(payload)
            case 2: pending = Array(payload); continue
            case 3: pending += payload; continue
            case 4: pending += payload
            default: pending = []; continue
            }
            if let entry = batch(pending, key: key), entry.seq >= found?.seq ?? 0 { found = entry }
            pending = []
        }
        return found
    }

    /// Snappy: длина варинтом, дальше литералы и ссылки назад.
    public static func snappy(_ input: [UInt8]) -> [UInt8]? {
        var r = Reader(input)
        guard let total = r.varint(), total <= 256 << 20 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(Int(total))
        while !r.atEnd {
            guard let tag = r.byte() else { return nil }
            var length: Int
            var distance: Int
            switch tag & 3 {
            case 0:
                length = Int(tag >> 2)
                if length >= 60 {
                    guard let extra = r.take(length - 59) else { return nil }
                    length = Int(littleEndian(extra))
                }
                guard let literal = r.take(length + 1) else { return nil }
                out += literal
                continue
            case 1:
                guard let low = r.byte() else { return nil }
                length = Int(tag >> 2 & 7) + 4
                distance = Int(tag >> 5) << 8 | Int(low)
            case 2:
                guard let raw = r.take(2) else { return nil }
                length = Int(tag >> 2) + 1
                distance = Int(littleEndian(raw))
            default:
                guard let raw = r.take(4) else { return nil }
                length = Int(tag >> 2) + 1
                distance = Int(littleEndian(raw))
            }
            guard distance > 0, distance <= out.count else { return nil }
            for _ in 0..<length { out.append(out[out.count - distance]) }
        }
        return out.count == Int(total) ? out : nil
    }

    // MARK: - Внутреннее

    /// Блок таблицы: данные и пятибайтовый хвост (тип сжатия + контрольная сумма).
    private static func block(_ data: Data, offset: UInt64, size: UInt64) -> [UInt8]? {
        guard offset < UInt64(data.count), size < UInt64(data.count),
              offset + size + 5 <= UInt64(data.count) else { return nil }
        let start = data.startIndex + Int(offset)
        let raw = [UInt8](data[start..<start + Int(size)])
        switch data[start + Int(size)] {
        case 0: return raw
        case 1: return snappy(raw)
        default: return nil
        }
    }

    /// Записи блока: ключи сжаты общим префиксом с предыдущим, в конце — таблица точек перезапуска.
    private static func entries(_ block: [UInt8]) -> [([UInt8], [UInt8])]? {
        guard block.count >= 4 else { return nil }
        let restarts = Int(littleEndian(block.suffix(4)))
        let end = block.count - 4 - restarts * 4
        guard restarts >= 0, end >= 0 else { return nil }
        var r = Reader(Array(block[..<end]))
        var key: [UInt8] = []
        var result: [([UInt8], [UInt8])] = []
        while !r.atEnd {
            guard let shared = r.varint(), let own = r.varint(), let valueLength = r.varint(),
                  shared <= UInt64(key.count),
                  let suffix = r.take(Int(own)), let value = r.take(Int(valueLength)) else { return nil }
            key = Array(key.prefix(Int(shared))) + suffix
            result.append((key, value))
        }
        return result
    }

    /// Пакет записи из журнала: номер, количество и подряд «положить»/«удалить».
    private static func batch(_ bytes: [UInt8], key: [UInt8]) -> Entry? {
        var r = Reader(bytes)
        guard let seqRaw = r.take(8), let countRaw = r.take(4) else { return nil }
        let seq = littleEndian(seqRaw)
        var found: Entry?
        for i in 0..<littleEndian(countRaw) {
            guard let op = r.byte(), let length = r.varint(), let k = r.take(Int(length)) else { return found }
            var value: [UInt8]?
            switch op {
            case 1:
                guard let vl = r.varint(), let v = r.take(Int(vl)) else { return found }
                value = v
            case 0: value = nil
            default: return found
            }
            if k == key { found = Entry(seq: seq &+ i, value: value) }
        }
        return found
    }

    private static func littleEndian<C: Collection>(_ bytes: C) -> UInt64 where C.Element == UInt8 {
        bytes.reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// Чтение по байтам с проверкой границ на каждом шаге.
    private struct Reader {
        let bytes: [UInt8]
        var pos = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { pos >= bytes.count }

        mutating func byte() -> UInt8? {
            guard pos < bytes.count else { return nil }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func take(_ n: Int) -> [UInt8]? {
            guard n >= 0, n <= bytes.count - pos else { return nil }
            defer { pos += n }
            return Array(bytes[pos..<pos + n])
        }

        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard let b = byte() else { return nil }
                result |= UInt64(b & 0x7f) << UInt64(shift)
                // Больше Int.max не бывает ни длины, ни смещения: такой варинт — мусор.
                if b < 0x80 { return result <= UInt64(Int.max) ? result : nil }
            }
            return nil
        }
    }
}
