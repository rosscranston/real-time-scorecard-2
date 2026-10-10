import Foundation

private final class AudioNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor OpenAITranscriber {
    public typealias EventHandler = @Sendable (AudioTranscriptEvent) -> Void
    public typealias ErrorHandler = @Sendable (String) -> Void
    private let key: String
    private let role: SpeakerRole
    private let origin: Date
    private let keywords: [String]
    private let onEvent: EventHandler
    private let onError: ErrorHandler
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var tracker = AudioCommitTracker()
    private var ready = false
    private var stopped = false
    public init(key: String, role: SpeakerRole, origin: Date, keywords: [String] = [],
                onEvent: @escaping EventHandler, onError: @escaping ErrorHandler) {
        self.key = key; self.role = role; self.origin = origin; self.keywords = Array(keywords.prefix(100))
        self.onEvent = onEvent; self.onError = onError
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: AudioNoRedirect(), delegateQueue: nil)
    }
    public func start() async throws {
        guard !ready else { return }
        stopped = false
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let connection = session.webSocketTask(with: request)
        socket = connection; connection.resume()
        let timeout = Task { try? await Task.sleep(for: .seconds(20)); if !Task.isCancelled { connection.cancel(with: .goingAway, reason: nil) } }
        defer { timeout.cancel() }
        do {
            let created = try await receive(connection)
            if created["type"] as? String == "error" { throw Self.providerError(created) }
            guard (created["type"] as? String)?.contains("created") == true else { throw OpenAIError.invalidResponse }
            try await send([
                "type": "session.update",
                "session": ["type": "transcription", "audio": ["input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "transcription": ["model": "gpt-live-transcribe", "languages": ["en"],
                                      "delay": "low", "keywords": keywords],
                    "turn_detection": NSNull()
                ]]]
            ], to: connection)
            for _ in 0..<8 {
                let event = try await receive(connection)
                if event["type"] as? String == "error" { throw Self.providerError(event) }
                if (event["type"] as? String)?.contains("updated") == true {
                    ready = true
                    receiver = Task { [weak self] in await self?.receiveLoop(connection) }
                    return
                }
            }
            throw OpenAIError.invalidResponse
        } catch {
            ready = false; socket = nil; connection.cancel(with: .normalClosure, reason: nil)
            throw (error as? OpenAIError) ?? .network
        }
    }
    public func submit(_ turn: AudioTurn) async throws {
        guard ready, let socket, !stopped else { throw OpenAIError.network }
        guard tracker.pendingCount < 12 else {
            throw DatabaseError(message: "Transcription fell behind; capture paused to avoid an unbounded audio buffer.")
        }
        tracker.enqueue(turn)
        do {
            try await send(["type": "input_audio_buffer.append", "audio": turn.pcm16.base64EncodedString()], to: socket)
            try await send(["type": "input_audio_buffer.commit"], to: socket)
        } catch {
            ready = false
            throw OpenAIError.network
        }
    }
    public func finish() async {
        // Allow final committed speech to finish, then release the network session.
        let deadline = Date().addingTimeInterval(8)
        while ready && tracker.pendingCount > 0 && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if tracker.pendingCount > 0 { onError("Some final audio was not transcribed before the connection closed.") }
        stopped = true; ready = false
        socket?.cancel(with: .normalClosure, reason: nil); receiver?.cancel()
        socket = nil; receiver = nil; session.invalidateAndCancel()
    }
    public func cancel() {
        stopped = true; ready = false; receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel()
    }
    private func receiveLoop(_ connection: URLSessionWebSocketTask) async {
        do {
            while !stopped && !Task.isCancelled {
                let event = try await receive(connection)
                switch event["type"] as? String {
                case "input_audio_buffer.committed":
                    guard let id = event["item_id"] as? String, tracker.acknowledged(itemID: id) else {
                        throw OpenAIError.invalidResponse
                    }
                case "conversation.item.input_audio_transcription.completed":
                    guard let id = event["item_id"] as? String,
                          let text = event["transcript"] as? String else { throw OpenAIError.invalidResponse }
                    guard let turn = tracker.finish(itemID: id) else { continue }
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onEvent(AudioTranscriptEvent(id: turn.id, role: role, text: text,
                            startSeconds: turn.startSeconds, sentenceEndedAt: origin.addingTimeInterval(turn.endSeconds)))
                    }
                case "conversation.item.input_audio_transcription.failed", "error":
                    throw Self.providerError(event)
                default: break
                }
            }
        } catch {
            ready = false
            if !stopped && !Task.isCancelled {
                onError((error as? OpenAIError)?.localizedDescription ?? "Audio connection failed; untranscribed audio may be missing.")
            }
        }
    }
    private func receive(_ connection: URLSessionWebSocketTask) async throws -> [String: Any] {
        let data: Data
        switch try await connection.receive() {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw OpenAIError.invalidResponse
        }
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OpenAIError.invalidResponse }
        return event
    }
    private func send(_ event: [String: Any], to connection: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        try await connection.send(.string(String(decoding: data, as: UTF8.self)))
    }
    private static func providerError(_ event: [String: Any]) -> OpenAIError {
        let error = event["error"] as? [String: Any] ?? [:]
        switch error["code"] as? String {
        case "insufficient_quota", "credit_balance_exhausted", "billing_hard_limit_reached": return .quota
        case "rate_limit_exceeded": return .rateLimited
        case "invalid_api_key", "authentication_error": return .authentication
        default: return .invalidResponse
        }
    }
}
