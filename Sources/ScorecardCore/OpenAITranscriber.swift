import Foundation

public actor OpenAITranscriber {
    public typealias EventHandler = @Sendable (AudioTranscriptEvent) -> Void
    public typealias ErrorHandler = @Sendable (String) -> Void
    public typealias ConnectionFactory = @Sendable (String) -> any TranscriptionConnection
    public typealias UsageHandler = @Sendable (Double) async throws -> Void
    private let key: String
    private let role: SpeakerRole
    private let origin: Date
    private let keywords: [String]
    private let onEvent: EventHandler
    private let onError: ErrorHandler
    private let onStatus: ErrorHandler
    private let onUsage: UsageHandler
    private let factory: ConnectionFactory
    private let retryDelay: Duration
    private let drainSeconds: Double
    private var socket: (any TranscriptionConnection)?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var generation = UUID()
    private var tracker = AudioCommitTracker()
    private var pending: [AudioTurn] = []
    private var sent = Set<UUID>()
    private var ready = false
    private var stopped = false
    private var finishing = false
    private var failed = false
    private var reconnects = 0

    public init(key: String, role: SpeakerRole, origin: Date, keywords: [String] = [],
                onEvent: @escaping EventHandler, onError: @escaping ErrorHandler,
                onStatus: @escaping ErrorHandler = { _ in },
                onUsage: @escaping UsageHandler = { _ in },
                connectionFactory: @escaping ConnectionFactory = { OpenAIAudioConnection(key: $0) },
                retryDelay: Duration = .seconds(1), drainSeconds: Double = 8) {
        self.key = key; self.role = role; self.origin = origin; self.keywords = Array(keywords.prefix(100))
        self.onEvent = onEvent; self.onError = onError; self.onStatus = onStatus
        self.onUsage = onUsage
        self.factory = connectionFactory; self.retryDelay = retryDelay; self.drainSeconds = drainSeconds
    }
    public func start() async throws {
        guard !ready else { return }
        guard socket == nil, !stopped, !failed else { throw OpenAIError.network }
        try await connect(generation: generation)
    }
    private func connect(generation current: UUID) async throws {
        let connection = factory(key)
        socket = connection
        await connection.start()
        let timeout = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { await connection.close() }
        }
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
                    guard generation == current, !stopped, !Task.isCancelled else { throw CancellationError() }
                    ready = true
                    receiver = Task { [weak self] in await self?.receiveLoop(connection, generation: current) }
                    pump()
                    return
                }
            }
            throw OpenAIError.invalidResponse
        } catch {
            await connection.close()
            if generation == current { ready = false; socket = nil }
            if error is CancellationError { throw error }
            throw (error as? OpenAIError) ?? .network
        }
    }
    public func submit(_ turn: AudioTurn) throws {
        guard !stopped, !finishing, !failed, ready || recovery != nil else { throw OpenAIError.network }
        guard !pending.contains(where: { $0.id == turn.id }) else { return }
        guard pending.count < 12 else {
            throw DatabaseError(message: "Transcription fell behind; capture paused to avoid an unbounded audio buffer.")
        }
        pending.append(turn); pump()
    }
    private func pump() {
        guard ready, !stopped, sender == nil, let socket else { return }
        let current = generation
        sender = Task { [weak self] in await self?.sendPending(socket, generation: current) }
    }
    private func sendPending(_ connection: any TranscriptionConnection, generation current: UUID) async {
        defer { if generation == current { sender = nil } }
        do {
            while generation == current, ready, !stopped, !Task.isCancelled,
                  let turn = pending.first(where: { !sent.contains($0.id) }) {
                sent.insert(turn.id); tracker.enqueue(turn)
                try await onUsage(Double(turn.pcm16.count) / 48000)
                guard generation == current, ready, !stopped else { return }
                try await send(["type": "input_audio_buffer.append", "audio": turn.pcm16.base64EncodedString()], to: connection)
                try await send(["type": "input_audio_buffer.commit"], to: connection)
            }
        } catch { await interrupted(error, generation: current) }
    }
    public func finish() async {
        finishing = true
        let deadline = Date().addingTimeInterval(drainSeconds)
        while !failed && !stopped && !pending.isEmpty && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !pending.isEmpty { onError("\(pending.count) audio segment(s) did not finish transcribing; those words may be missing.") }
        await cancel()
    }
    public func cancel() async {
        stopped = true; ready = false; generation = UUID()
        receiver?.cancel(); sender?.cancel(); recovery?.cancel()
        let connection = socket; socket = nil
        await connection?.close()
        receiver = nil; sender = nil; recovery = nil
        pending.removeAll(); sent.removeAll(); tracker = AudioCommitTracker()
    }
    private func receiveLoop(_ connection: any TranscriptionConnection, generation current: UUID) async {
        do {
            while !stopped && !Task.isCancelled && generation == current {
                let event = try await receive(connection)
                guard generation == current, !stopped else { return }
                switch event["type"] as? String {
                case "input_audio_buffer.committed":
                    guard let id = event["item_id"] as? String, tracker.acknowledged(itemID: id) else {
                        throw OpenAIError.invalidResponse
                    }
                case "conversation.item.input_audio_transcription.completed":
                    guard let id = event["item_id"] as? String,
                          let text = event["transcript"] as? String else { throw OpenAIError.invalidResponse }
                    guard let turn = tracker.finish(itemID: id) else { continue }
                    pending.removeAll { $0.id == turn.id }; sent.remove(turn.id)
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onEvent(AudioTranscriptEvent(id: turn.id, role: role, text: text,
                            startSeconds: turn.startSeconds, sentenceEndedAt: origin.addingTimeInterval(turn.endSeconds)))
                    }
                case "conversation.item.input_audio_transcription.failed", "error":
                    throw Self.providerError(event)
                default: break
                }
            }
        } catch { await interrupted(error, generation: current) }
    }
    private func interrupted(_ error: Error, generation current: UUID) async {
        guard current == generation, !stopped else { return }
        // Invalidate both old lanes before awaiting close: one network failure must
        // not launch two reconnect workers or allow a late completion to commit.
        ready = false; generation = UUID()
        receiver?.cancel(); sender?.cancel(); receiver = nil; sender = nil
        let connection = socket; socket = nil
        tracker = AudioCommitTracker(); sent.removeAll()
        let apiError = (error as? OpenAIError) ?? .network
        if apiError == .network, reconnects < 2 {
            onStatus("\(role.rawValue.capitalized) audio reconnecting…")
            recovery = Task { [weak self] in await self?.reconnect() }
        } else {
            failed = true
            onError("\(apiError.localizedDescription) Untranscribed audio may be missing; reconnect explicitly to continue.")
        }
        await connection?.close()
    }
    private func reconnect() async {
        let current = generation
        defer { if generation == current { recovery = nil } }
        while reconnects < 2 && !stopped && generation == current {
            reconnects += 1
            do {
                try await Task.sleep(for: retryDelay * reconnects)
                guard !stopped, generation == current else { return }
                try await connect(generation: current)
                guard ready, generation == current, !stopped else { return }
                onStatus("OpenAI audio")
                return
            } catch {
                if stopped || generation != current || error is CancellationError { return }
                if let apiError = error as? OpenAIError, apiError != .network {
                    failed = true; onError(apiError.localizedDescription); return
                }
            }
        }
        if !stopped && generation == current {
            failed = true
            onError("Audio reconnect attempts exhausted; untranscribed audio may be missing. Reconnect in Settings.")
        }
    }
    private func receive(_ connection: any TranscriptionConnection) async throws -> [String: Any] {
        let data = try await connection.receive()
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OpenAIError.invalidResponse }
        return event
    }
    private func send(_ event: [String: Any], to connection: any TranscriptionConnection) async throws {
        try await connection.send(JSONSerialization.data(withJSONObject: event))
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
