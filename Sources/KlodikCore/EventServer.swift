import Foundation
import Network

/// HTTP-приёмник событий хуков: `POST /klodik/event` на 127.0.0.1. Отвечает сразу пустым `200` —
/// никаких решений за пользователя (важно для `PermissionRequest`), и Claude не ждёт Клодика.
public final class EventServer {
    public enum State: Equatable {
        case ready(port: UInt16)
        /// Чаще всего порт занят другим приложением.
        case failed(String)
    }

    public static let defaultPort: UInt16 = 47821
    /// Адрес в URL хука. Своё имя в пути — чтобы по нему отличать хуки Клодика от чужих в settings.json.
    public static let path = "/klodik/event"
    /// Сколько ждать запрос от открытого соединения, прежде чем закрыть его.
    static let connectionTimeout: TimeInterval = 5

    public let requestedPort: UInt16
    /// Вызываются на главной очереди.
    public var onEvent: ((HookEvent) -> Void)?
    public var onState: ((State) -> Void)?

    private let queue = DispatchQueue(label: "klodik.event-server")
    private var listener: NWListener?

    /// `port: 0` — любой свободный порт (для тестов), настоящий придёт в `.ready`.
    public init(port: UInt16 = EventServer.defaultPort) {
        requestedPort = port
    }

    deinit { stop() }

    public func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        let port = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)   // только этот компьютер
        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            report(.failed("\(error)"))
            return
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                self?.report(.ready(port: listener?.port?.rawValue ?? 0))
            case .failed(let error):
                self?.report(.failed("\(error)"))
                listener?.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func report(_ state: State) {
        DispatchQueue.main.async { self.onState?(state) }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { [weak connection] in connection?.cancel() }
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil { connection.cancel() } else { self.receive(connection, buffer: buffer) }
            case .tooLarge:
                self.respond(connection, "413 Payload Too Large")
            case .invalid:
                self.respond(connection, "400 Bad Request")
            case let .request(method, path, body):
                guard method == "POST", path == Self.path else {
                    self.respond(connection, "404 Not Found")
                    return
                }
                self.respond(connection, "200 OK")
                if let event = HookEvent.parse(body) {
                    DispatchQueue.main.async { self.onEvent?(event) }
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, _ status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
