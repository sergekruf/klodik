import Foundation

/// Новая версия на GitHub: раз в сутки спросить последний релиз и сравнить с установленной.
public enum UpdateCheck {
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/sergekruf/klodik/releases/latest")!
    public static let every: TimeInterval = 24 * 3600

    public struct Release: Equatable {
        public var version: String
        public var url: URL

        public init(version: String, url: URL) {
            self.version = version; self.url = url
        }
    }

    /// Ответ GitHub API → версия без «v» и страница релиза.
    public static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: page)
    }

    /// «0.2.0» новее «0.1.10»? Сравнение по числам, недостающие части — нули.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
