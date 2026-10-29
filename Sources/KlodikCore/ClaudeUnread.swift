import Foundation
import CoreServices

/// Сессии, которые пользователь сам отметил непрочитанными в Claude (правый клик → «Отметить непрочитанным»).
/// Приложение хранит их не в файлах сессий, а в localStorage своей веб-части: LevelDB в `Local Storage/leveldb`,
/// ключ `epitaxy-unread-v1`, значение `{"state":{"unreadIds":[…],"explicitUnreadIds":[…]}}`.
/// Формат нигде не описан и может поменяться с любым обновлением Claude. Тогда `read()` вернёт nil,
/// и Клодик просто живёт без этих пометок, как раньше.
public final class ClaudeUnread {
    /// KLODIK_CLAUDE_STORAGE_DIR — другая папка (демо и тесты).
    public static var defaultRoot: URL {
        if let dir = ProcessInfo.processInfo.environment["KLODIK_CLAUDE_STORAGE_DIR"] { return URL(fileURLWithPath: dir) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude/Local Storage/leveldb")
    }

    /// Ключ localStorage Chromium: `_` + origin + `\0` + `\1` (строка в Latin-1) + имя ключа.
    static let key = Array("_https://claude.ai".utf8) + [0, 1] + Array("epitaxy-unread-v1".utf8)

    public let root: URL
    /// Вызывается, когда в базе что-то поменялось, на главной очереди. Пометки ещё надо перечитать.
    public var onChange: (() -> Void)?

    /// Разобранные файлы: путь → размер и дата изменения на момент чтения и что в нём нашлось.
    /// Таблицы `.ldb` не меняются, а самая большая весит десятки мегабайт: читаем каждую один раз.
    private var cache: [String: (size: Int, modified: Date, entry: LevelDB.Entry?)] = [:]
    private var stream: FSEventStreamRef?

    public init(root: URL = ClaudeUnread.defaultRoot) {
        self.root = root
    }

    deinit { stopWatching() }

    /// `localId` отмеченных сессий. nil — база не читается или формат не тот; пустое множество — отметок нет.
    public func read() -> Set<String>? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        var newest: LevelDB.Entry?
        var seen: Set<String> = []
        for name in names where name.hasSuffix(".ldb") || name.hasSuffix(".log") {
            let path = root.appendingPathComponent(name).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.intValue,
                  let modified = attrs[.modificationDate] as? Date else { continue }   // удалили во время обхода
            seen.insert(path)
            let entry: LevelDB.Entry?
            if let cached = cache[path], cached.size == size, cached.modified == modified {
                entry = cached.entry
            } else {
                let parsed: LevelDB.Entry?? = autoreleasepool {
                    // Журнал дописывается на ходу — его копируем, а не отображаем в память.
                    let options: Data.ReadingOptions = name.hasSuffix(".ldb") ? .mappedIfSafe : []
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: options) else {
                        return .some(nil)                                              // удалили во время обхода
                    }
                    return name.hasSuffix(".ldb") ? LevelDB.lookup(table: data, key: Self.key)
                                                  : .some(LevelDB.lookup(log: [UInt8](data), key: Self.key))
                }
                guard let parsed else { return nil }
                entry = parsed
                cache[path] = (size, modified, entry)
            }
            if let entry, entry.seq >= newest?.seq ?? 0 { newest = entry }
        }
        cache = cache.filter { seen.contains($0.key) }
        guard let newest else { return [] }
        guard let value = newest.value else { return [] }
        return Self.parse(value)
    }

    /// Значение localStorage: первый байт — кодировка (0 — UTF-16LE, 1 — Latin-1), дальше JSON.
    static func parse(_ value: [UInt8]) -> Set<String>? {
        guard let encoding = value.first else { return nil }
        let body = Data(value.dropFirst())
        let text: String?
        switch encoding {
        case 0: text = String(data: body, encoding: .utf16LittleEndian)
        case 1: text = String(data: body, encoding: .isoLatin1)
        default: return nil
        }
        guard let data = text?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? [String: Any] else { return nil }
        // Ключа нет — значит, отметок ещё ни разу не ставили.
        guard let ids = state["explicitUnreadIds"] else { return [] }
        guard let list = ids as? [String] else { return nil }
        return Set(list)
    }

    public func startWatching(latency: TimeInterval = 1) {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ClaudeUnread>.fromOpaque(info).takeUnretainedValue().onChange?()
        }
        guard let created = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    public func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
