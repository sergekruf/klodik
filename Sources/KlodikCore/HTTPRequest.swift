import Foundation

/// Минимальный разбор HTTP-запроса от хука: строка запроса, Content-Length, тело.
/// Ничего сверх этого Клодику не нужно, поэтому без библиотек.
public enum HTTPRequest {
    public static let maxBody = 64 * 1024
    public static let maxHeader = 8 * 1024

    public enum ParseResult: Equatable {
        /// Нужно дочитать ещё.
        case incomplete
        case tooLarge
        case invalid
        case request(method: String, path: String, body: Data)
    }

    public static func parse(_ buffer: Data) -> ParseResult {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeader ? .invalid : .incomplete
        }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/") else { return .invalid }

        var length = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            guard let value = Int(pair[1].trimmingCharacters(in: .whitespaces)), value >= 0 else { return .invalid }
            length = value
        }
        if length > maxBody { return .tooLarge }

        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .incomplete }
        return .request(method: String(requestLine[0]), path: String(requestLine[1]),
                        body: Data(buffer[bodyStart..<(bodyStart + length)]))
    }
}
