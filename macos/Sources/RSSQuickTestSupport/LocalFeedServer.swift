import Foundation
import Network

/// Serves canned feeds on a loopback port.
///
/// The point is to exercise the real `FeedLoader` - the real `URLSession`, the real timeout, the
/// real concurrency cap - against a server the test controls, rather than to stub the loader out
/// and test a fake. Nothing in the application had to grow an interface to make this possible.
public final class LocalFeedServer: @unchecked Sendable {
    /// What one path answers with.
    public struct Route: Sendable {
        public let status: Int
        public let body: Data
        public let contentType: String
        /// How long the server sits on the request before answering. Used to make a feed slow
        /// enough that the concurrency cap and the cancellation path can be observed.
        public let delay: TimeInterval

        public init(status: Int = 200, body: String, contentType: String = "application/rss+xml", delay: TimeInterval = 0) {
            self.status = status
            self.body = Data(body.utf8)
            self.contentType = contentType
            self.delay = delay
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalFeedServer", attributes: .concurrent)
    private let lock = NSLock()

    private var routes: [String: Route]
    private var _inFlight = 0
    private var _peakInFlight = 0
    private var _requestCount = 0

    public private(set) var port: UInt16 = 0

    /// The greatest number of requests the server was handling at one moment.
    public var peakInFlight: Int { lock.withLock { _peakInFlight } }

    /// How many requests arrived in total.
    public var requestCount: Int { lock.withLock { _requestCount } }

    public init(routes: [String: Route]) throws {
        self.routes = routes

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)

        let ready = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.port = self?.listener.port?.rawValue ?? 0
                ready.signal()
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            throw Failure.didNotStart
        }
    }

    public enum Failure: Error { case didNotStart }

    deinit { listener.cancel() }

    public func stop() { listener.cancel() }

    public func url(for path: String) -> String { "http://127.0.0.1:\(port)\(path)" }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let data { accumulated.append(data) }

            guard error == nil else { connection.cancel(); return }

            // The whole request line and headers have arrived once the blank line has.
            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self)
                respond(on: connection, to: head)
                return
            }

            if isComplete { connection.cancel(); return }

            receive(connection, buffer: accumulated)
        }
    }

    private func respond(on connection: NWConnection, to head: String) {
        let path = head
            .split(separator: "\r\n").first
            .map { $0.split(separator: " ") }
            .flatMap { $0.count >= 2 ? String($0[1]) : nil } ?? "/"

        let route = lock.withLock { () -> Route? in
            _requestCount += 1
            _inFlight += 1
            _peakInFlight = Swift.max(_peakInFlight, _inFlight)
            return routes[path]
        }

        let finish = {
            self.lock.withLock { self._inFlight -= 1 }

            guard let route else {
                connection.send(content: Self.response(status: 404, body: Data(), contentType: "text/plain"), completion: .contentProcessed { _ in connection.cancel() })
                return
            }

            let payload = Self.response(status: route.status, body: route.body, contentType: route.contentType)
            connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
        }

        if let route, route.delay > 0 {
            queue.asyncAfter(deadline: .now() + route.delay) { finish() }
        } else {
            finish()
        }
    }

    private static func response(status: Int, body: Data, contentType: String) -> Data {
        var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(body)
        return payload
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
