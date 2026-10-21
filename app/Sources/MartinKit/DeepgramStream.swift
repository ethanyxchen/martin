import Foundation

public final class DeepgramStream: @unchecked Sendable {
    static let bytesPerSecond = 32000
    static let backlogLimit = 8_000_000
    static let keytermBudget = 1000

    private let queue = DispatchQueue(label: "dev.ethanchen.martin.deepgram")
    private let request: URLRequest
    private let events = Events()
    private lazy var session = URLSession(configuration: .default, delegate: events, delegateQueue: Self.operationQueue(on: queue))
    private var task: URLSessionWebSocketTask?
    private var open = false
    private var stopped = false
    private var backlog = Data()
    private var bytesBeforeSocket = 0
    private var bytesOnSocket = 0
    private var lastSent = Date.now
    private var retryDelay = 0.5
    private var keepAlive: DispatchSourceTimer?
    private var finishing: CheckedContinuation<Void, Never>?
    private var onSegment: @Sendable (Segment) -> Void = { _ in }
    private var onError: @Sendable (String) -> Void = { _ in }

    public convenience init(apiKey: String, keyterms: [String]) {
        var request = URLRequest(url: Self.url(keyterms: keyterms))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        self.init(request: request)
    }

    init(request: URLRequest) {
        self.request = request
        events.stream = self
    }

    public func connect(onSegment: @escaping @Sendable (Segment) -> Void, onError: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            guard task == nil, !stopped else { return }
            self.onSegment = onSegment
            self.onError = onError
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.keepAliveIfIdle() }
            timer.resume()
            keepAlive = timer
            dial()
        }
    }

    public func send(_ audio: Data) {
        queue.async { [self] in
            guard !stopped else { return }
            guard open, let task else { return buffer(audio) }
            transmit(audio, on: task)
        }
    }

    public func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopped = true
                keepAlive?.cancel()
                guard open, let task else { return close(continuation) }
                finishing = continuation
                task.send(.string(#"{"type":"CloseStream"}"#)) { _ in }
                queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, let finishing else { return }
                    close(finishing)
                }
            }
        }
    }

    public static func segment(from message: Data) -> Segment? {
        guard let result = try? decoder.decode(Result.self, from: message), result.type == "Results", result.isFinal,
              let text = result.channel.alternatives.first?.transcript.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return Segment(at: result.start, duration: result.duration, text: text)
    }

    static func url(keyterms: [String]) -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen?model=nova-3&encoding=linear16&sample_rate=16000&channels=1&smart_format=true&interim_results=false&mip_opt_out=true")!
        var budget = keytermBudget
        let terms = keyterms.prefix { term in
            budget -= term.count
            return budget >= 0
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedQueryItems! += terms.map { URLQueryItem(name: "keyterm", value: $0.addingPercentEncoding(withAllowedCharacters: allowed)) }
        return components.url!
    }

    static func failure(closeCode: Int, status: Int?) -> String? {
        switch (closeCode, status) {
        case (_, 401?), (_, 403?): "Deepgram rejected the API key."
        case (_, let status?) where (400..<500).contains(status) && status != 408 && status != 429: "Deepgram refused the connection (HTTP \(status))."
        case (1002, _), (1003, _), (1007, _), (1008, _), (1009, _): "Deepgram closed the stream (code \(closeCode))."
        default: nil
        }
    }

    private func dial() {
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive(on: task)
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.task, case .success(let message) = result else { return }
            if let segment = Self.segment(from: message.data) {
                onSegment(Segment(at: segment.at + Double(bytesBeforeSocket) / Double(Self.bytesPerSecond), duration: segment.duration, text: segment.text))
            }
            receive(on: task)
        }
    }

    fileprivate func opened(_ socket: URLSessionWebSocketTask) {
        guard socket === task else { return }
        open = true
        retryDelay = 0.5
        let pending = backlog
        backlog = Data()
        for start in stride(from: pending.startIndex, to: pending.endIndex, by: Self.bytesPerSecond) {
            transmit(pending[start..<min(start + Self.bytesPerSecond, pending.endIndex)], on: socket)
        }
    }

    fileprivate func ended(_ socket: URLSessionWebSocketTask) {
        guard socket === task else { return }
        task = nil
        open = false
        bytesBeforeSocket += bytesOnSocket
        bytesOnSocket = 0
        if let finishing { return close(finishing) }
        guard !stopped else { return }
        let status = (socket.response as? HTTPURLResponse)?.statusCode
        Log.transcription.notice("Deepgram socket closed with code \(socket.closeCode.rawValue), HTTP \(status ?? 0): \(socket.error?.localizedDescription ?? "no error", privacy: .public)")
        if let message = Self.failure(closeCode: socket.closeCode.rawValue, status: status) {
            stopped = true
            keepAlive?.cancel()
            session.invalidateAndCancel()
            Log.transcription.error("Transcription stopped: \(message, privacy: .public)")
            return onError(message)
        }
        queue.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self, !stopped, task == nil else { return }
            dial()
        }
        retryDelay = min(retryDelay * 2, 5)
    }

    private func transmit(_ audio: Data, on socket: URLSessionWebSocketTask) {
        socket.send(.data(audio)) { _ in }
        bytesOnSocket += audio.count
        lastSent = .now
    }

    private func buffer(_ audio: Data) {
        backlog.append(audio)
        let overflow = backlog.count - Self.backlogLimit
        guard overflow > 0 else { return }
        backlog.removeFirst(overflow)
        bytesBeforeSocket += overflow
    }

    private func keepAliveIfIdle() {
        guard open, let task, Date.now.timeIntervalSince(lastSent) >= 5 else { return }
        task.send(.string(#"{"type":"KeepAlive"}"#)) { _ in }
        lastSent = .now
    }

    private func close(_ continuation: CheckedContinuation<Void, Never>) {
        finishing = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        open = false
        session.invalidateAndCancel()
        continuation.resume()
    }

    private static func operationQueue(on queue: DispatchQueue) -> OperationQueue {
        let operations = OperationQueue()
        operations.underlyingQueue = queue
        operations.maxConcurrentOperationCount = 1
        return operations
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private struct Result: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable { let transcript: String }
            let alternatives: [Alternative]
        }
        let type: String
        let isFinal: Bool
        let start: Double
        let duration: Double
        let channel: Channel
    }
}

private final class Events: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    weak var stream: DeepgramStream?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        stream?.opened(webSocketTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let socket = task as? URLSessionWebSocketTask else { return }
        stream?.ended(socket)
    }
}

private extension URLSessionWebSocketTask.Message {
    var data: Data {
        switch self {
        case .data(let data): data
        case .string(let string): Data(string.utf8)
        @unknown default: Data()
        }
    }
}
