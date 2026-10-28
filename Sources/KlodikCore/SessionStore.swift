import Foundation
import CoreServices

/// Все сессии вкладки Code из файлов приложения Claude.
/// При старте читает всё один раз, дальше перечитывает только файлы, о которых сообщил FSEvents.
public final class SessionStore {
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude/claude-code-sessions")
    }

    public let root: URL
    /// Ключ — `localId`.
    public private(set) var sessions: [String: SessionInfo] = [:]
    /// Папки нет или ни один файл не разобрался: Клодик работает только по хукам и предупреждает в меню.
    public private(set) var formatBroken = false
    /// Вызывается после каждого изменения, на главной очереди.
    public var onChange: (() -> Void)?

    private var idByPath: [String: String] = [:]
    private var stream: FSEventStreamRef?

    public init(root: URL = SessionStore.defaultRoot) {
        self.root = root
    }

    deinit { stopWatching() }

    public func loadAll() {
        sessions = [:]
        idByPath = [:]
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            formatBroken = true
            onChange?()
            return
        }
        var total = 0
        for path in sessionFilePaths() {
            total += 1
            read(path)
        }
        formatBroken = total > 0 && sessions.isEmpty
        onChange?()
    }

    /// Перечитать указанные файлы. Пропавший файл — сессию убрать, недописанный — оставить прежнее значение.
    public func reload(paths: [String]) {
        var changed = false
        for raw in paths where SessionFile.isSessionFile((raw as NSString).lastPathComponent) {
            let path = Self.normalized(raw)
            if FileManager.default.fileExists(atPath: path) {
                changed = read(path) || changed
            } else if let id = idByPath.removeValue(forKey: path) {
                sessions[id] = nil
                // Если у сессии осталась копия в папке другого аккаунта — показать её.
                for (other, otherId) in idByPath where otherId == id { read(other) }
                changed = true
            }
        }
        if changed {
            if !sessions.isEmpty { formatBroken = false }
            onChange?()
        }
    }

    public func startWatching(latency: TimeInterval = 0.5) {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let store = Unmanaged<SessionStore>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            store.reload(paths: list)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let created = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                latency, flags) else { return }
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

    /// `<аккаунт>/<организация>/local_*.json` — ровно два уровня папок, без рекурсивного обхода.
    private func sessionFilePaths() -> [String] {
        let fm = FileManager.default
        func children(_ dir: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).map { (dir as NSString).appendingPathComponent($0) }
        }
        return children(Self.normalized(root.path))
            .flatMap(children)
            .flatMap(children)
            .filter { SessionFile.isSessionFile(($0 as NSString).lastPathComponent) }
    }

    /// true, если сессия добавилась или поменялась.
    /// Одна сессия может лежать копиями в папках разных аккаунтов — побеждает самая свежая по активности.
    @discardableResult
    private func read(_ path: String) -> Bool {
        // Файлы сессий вместе весят десятки мегабайт: без своего autoreleasepool прочитанные данные
        // копятся до конца обхода, и процесс навсегда остаётся с раздутой кучей.
        let parsed: SessionInfo? = autoreleasepool {
            FileManager.default.contents(atPath: path).flatMap(SessionFile.parse)
        }
        guard let info = parsed else { return false }
        idByPath[path] = info.localId
        if let current = sessions[info.localId] {
            if current == info { return false }
            if (current.lastActivityAt ?? .distantPast) > (info.lastActivityAt ?? .distantPast) { return false }
        }
        sessions[info.localId] = info
        return true
    }

    /// FSEvents отдаёт пути без символьных ссылок (/private/var вместо /var) — приводим всё к одному виду.
    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
