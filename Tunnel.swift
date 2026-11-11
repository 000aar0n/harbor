import Foundation
import Network

// Browser-only CONNECT proxy bound exclusively to loopback. Each stream is
// carried over an authenticated TLS WebSocket; destination TLS stays end to end.
final class HarborTunnel {
    private let queue = DispatchQueue(label: "harbor.tunnel")
    private var listener: NWListener?
    private var streams: [UUID: TunnelStream] = [:]
    private let endpoint: URL
    private let token: String
    private let session = URLSession(configuration: .ephemeral)
    init(endpoint: URL, token: String) { self.endpoint = endpoint; self.token = token }

    func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            var completed = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !completed, let port = listener.port { completed = true; completion(.success(port.rawValue)) }
                case .failed(let error):
                    if !completed { completed = true; completion(.failure(error)) }
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                let id = UUID()
                let stream = TunnelStream(connection: connection, endpoint: self.endpoint, token: self.token, session: self.session, queue: self.queue) { self.streams.removeValue(forKey: id) }
                self.streams[id] = stream
                stream.start()
            }
            listener.start(queue: queue)
        } catch { completion(.failure(error)) }
    }
    func stop() {
        queue.async {
            self.listener?.cancel()
            let current = Array(self.streams.values)
            current.forEach { $0.close() }
            self.session.invalidateAndCancel()
        }
    }
}

private final class TunnelStream {
    let connection: NWConnection
    let endpoint: URL
    let token: String
    let session: URLSession
    let queue: DispatchQueue
    let finished: () -> Void
    var socket: URLSessionWebSocketTask?
    var header = Data()
    var closed = false
    var timeout: DispatchWorkItem?
    init(connection: NWConnection, endpoint: URL, token: String, session: URLSession, queue: DispatchQueue, finished: @escaping () -> Void) {
        self.connection = connection; self.endpoint = endpoint; self.token = token
        self.session = session; self.queue = queue; self.finished = finished
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
        }
        connection.start(queue: queue)
        let deadline = DispatchWorkItem { [weak self] in self?.close() }
        timeout = deadline
        queue.asyncAfter(deadline: .now() + 90, execute: deadline)
        readHeader()
    }
    func close() {
        guard !closed else { return }
        closed = true
        timeout?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        connection.cancel()
        finished()
    }
    func readHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            if let data = data { self.header.append(data) }
            if let range = self.header.range(of: Data("\r\n\r\n".utf8)) {
                guard let text = String(data: self.header[..<range.lowerBound], encoding: .utf8), let first = text.components(separatedBy: "\r\n").first else { self.close(); return }
                let parts = first.split(separator: " ")
                guard parts.count == 3, parts[0] == "CONNECT", let url = URL(string: "https://" + parts[1]), let host = url.host, let port = url.port, [80, 443].contains(port), url.user == nil, url.password == nil else {
                    self.connection.send(content: Data("HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in self.close() }); return
                }
                let extra = Data(self.header[range.upperBound...])
                self.open(host: host, port: port, extra: extra)
            } else if self.header.count > 16384 || complete || error != nil { self.close() }
            else { self.readHeader() }
        }
    }
    func open(host: String, port: Int, extra: Data) {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        let opening = try! JSONSerialization.data(withJSONObject: ["host": host, "port": port])
        socket.send(.string(String(data: opening, encoding: .utf8)!)) { [weak self] error in
            guard let self = self else { return }
            if error != nil { self.queue.async { self.close() }; return }
            socket.receive { result in
                self.queue.async {
                    guard case .success(.string("ready")) = result else { self.close(); return }
                    self.timeout?.cancel()
                    self.connection.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { error in
                        if error != nil { self.close(); return }
                        self.receiveRemote()
                        if extra.isEmpty { self.receiveLocal() }
                        else { self.sendRemote(extra) }
                    })
                }
            }
        }
    }
    func sendRemote(_ data: Data) {
        socket?.send(.data(data)) { [weak self] error in
            guard let self = self else { return }
            self.queue.async { if error != nil { self.close() } else { self.receiveLocal() } }
        }
    }
    func receiveLocal() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self = self, !self.closed else { return }
            if error != nil || complete { self.close() }
            else if let data = data, !data.isEmpty { self.sendRemote(data) }
            else { self.receiveLocal() }
        }
    }
    func receiveRemote() {
        socket?.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                guard !self.closed, case .success(.data(let data)) = result else { self.close(); return }
                self.connection.send(content: data, completion: .contentProcessed { error in
                    if error != nil { self.close() } else { self.receiveRemote() }
                })
            }
        }
    }
}
