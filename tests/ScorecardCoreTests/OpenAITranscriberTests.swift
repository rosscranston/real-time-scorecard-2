import XCTest
@testable import ScorecardCore

private actor FakeAudioConnection: TranscriptionConnection {
    enum Mode { case success, dropCommit, quota, silent }
    let mode: Mode
    var messages: [Data] = []
    var waiting: CheckedContinuation<Data, Error>?
    var closed = false
    var commits = 0
    init(_ mode: Mode) { self.mode = mode }
    func emit(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        if let waiting { self.waiting = nil; waiting.resume(returning: data) }
        else { messages.append(data) }
    }
    func start() async { try? emit(["type": "session.created"]) }
    func send(_ data: Data) async throws {
        if closed { throw OpenAIError.network }
        let event = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        switch event["type"] as? String {
        case "session.update":
            if mode == .quota { try emit(["type": "error", "error": ["code": "credit_balance_exhausted"]]) }
            else { try emit(["type": "session.updated"]) }
        case "input_audio_buffer.commit":
            commits += 1
            if mode == .dropCommit { throw OpenAIError.network }
            if mode == .silent { return }
            let id = "item-\(commits)"
            try emit(["type": "input_audio_buffer.committed", "item_id": id])
            try emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": id, "transcript": "We use Drake Desktop."])
            // Duplicate completion must be harmless.
            try emit(["type": "conversation.item.input_audio_transcription.completed", "item_id": id, "transcript": "We use Drake Desktop."])
        default: break
        }
    }
    func receive() async throws -> Data {
        if closed { throw OpenAIError.network }
        if !messages.isEmpty { return messages.removeFirst() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func close() async {
        closed = true
        waiting?.resume(throwing: OpenAIError.network); waiting = nil
    }
}
private final class FakeAudioFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0
    let connections: [FakeAudioConnection]
    init(_ modes: [FakeAudioConnection.Mode]) { connections = modes.map(FakeAudioConnection.init) }
    func next(_ key: String) -> any TranscriptionConnection {
        lock.withLock {
            let result = connections[min(index, connections.count - 1)]
            index += 1
            return result
        }
    }
    var count: Int { lock.withLock { index } }
}
private final class AudioOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AudioTranscriptEvent] = []
    private var errors: [String] = []
    func event(_ value: AudioTranscriptEvent) { lock.withLock { events.append(value) } }
    func error(_ value: String) { lock.withLock { errors.append(value) } }
    var snapshot: ([AudioTranscriptEvent], [String]) { lock.withLock { (events, errors) } }
}

final class OpenAITranscriberTests: XCTestCase {
    func testAudioAllowanceStopsBeforeUploadWithoutReconnect() async throws {
        let factory = FakeAudioFactory([.success])
        let results = AudioOutcomes()
        let billing = try OpenAIClient(key: "test", budgetUSD: 0.00001)
        let transcriber = OpenAITranscriber(key: "test", role: .customer, origin: Date(),
            onEvent: { results.event($0) }, onError: { results.error($0) },
            onUsage: { try await billing.recordAudioUpload(seconds: $0) },
            connectionFactory: { factory.next($0) })
        try await transcriber.start()
        try await transcriber.submit(AudioTurn(pcm16: Data(repeating: 0, count: 4800), startSeconds: 0, endSeconds: 0.1))
        await transcriber.finish()
        let commits = await factory.connections[0].commits
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(factory.count, 1)
        XCTAssertTrue(results.snapshot.1.contains { $0.contains("allowance") })
        let usage = await billing.usage()
        XCTAssertEqual(usage.chargedOrReservedUSD, 0)
    }
    func testDisconnectResendsUnfinishedAudioOnceWithOriginalIdentity() async throws {
        let factory = FakeAudioFactory([.dropCommit, .success])
        let results = AudioOutcomes()
        let origin = Date(timeIntervalSince1970: 1000)
        let transcriber = OpenAITranscriber(key: "test", role: .customer, origin: origin,
            onEvent: { results.event($0) }, onError: { results.error($0) }, connectionFactory: { factory.next($0) }, retryDelay: .milliseconds(1))
        try await transcriber.start()
        let turn = AudioTurn(pcm16: Data(repeating: 0, count: 4800), startSeconds: 3, endSeconds: 4)
        try await transcriber.submit(turn)
        await transcriber.finish()
        XCTAssertEqual(factory.count, 2)
        XCTAssertTrue(results.snapshot.1.isEmpty)
        XCTAssertEqual(results.snapshot.0.count, 1)
        XCTAssertEqual(results.snapshot.0.first?.id, turn.id)
        XCTAssertEqual(results.snapshot.0.first?.sentenceEndedAt, origin.addingTimeInterval(4))
        XCTAssertEqual(results.snapshot.0.first?.role, .customer)
    }
    func testAudioQuotaDoesNotReconnectAndCancelRejectsLateSubmissions() async throws {
        let factory = FakeAudioFactory([.quota, .success])
        let results = AudioOutcomes()
        let transcriber = OpenAITranscriber(key: "test", role: .customer, origin: Date(),
            onEvent: { results.event($0) }, onError: { results.error($0) }, connectionFactory: { factory.next($0) }, retryDelay: .milliseconds(1))
        do { try await transcriber.start(); XCTFail("Expected quota error") }
        catch { XCTAssertEqual(error as? OpenAIError, .quota) }
        XCTAssertEqual(factory.count, 1)
        await transcriber.cancel()
        do { try await transcriber.submit(AudioTurn(pcm16: Data(), startSeconds: 0, endSeconds: 1)); XCTFail() }
        catch { XCTAssertEqual(error as? OpenAIError, .network) }
        XCTAssertTrue(results.snapshot.0.isEmpty)
    }
    func testReconnectAttemptsAreBoundedAndReportMissingAudio() async throws {
        let factory = FakeAudioFactory([.dropCommit, .dropCommit, .dropCommit, .success])
        let results = AudioOutcomes()
        let transcriber = OpenAITranscriber(key: "test", role: .customer, origin: Date(),
            onEvent: { results.event($0) }, onError: { results.error($0) }, connectionFactory: { factory.next($0) }, retryDelay: .milliseconds(1))
        try await transcriber.start()
        try await transcriber.submit(AudioTurn(pcm16: Data(repeating: 0, count: 4800), startSeconds: 0, endSeconds: 1))
        await transcriber.finish()
        XCTAssertEqual(factory.count, 3)
        XCTAssertFalse(results.snapshot.1.isEmpty)
        XCTAssertTrue(results.snapshot.0.isEmpty)
    }
    func testBoundedQueueAndDrainTimeoutNeverPretendAudioWasTranscribed() async throws {
        let factory = FakeAudioFactory([.silent])
        let results = AudioOutcomes()
        let transcriber = OpenAITranscriber(key: "test", role: .customer, origin: Date(),
            onEvent: { results.event($0) }, onError: { results.error($0) }, connectionFactory: { factory.next($0) }, drainSeconds: 0.03)
        try await transcriber.start()
        for _ in 0..<12 { try await transcriber.submit(AudioTurn(pcm16: Data(repeating: 0, count: 4800), startSeconds: 0, endSeconds: 1)) }
        do { try await transcriber.submit(AudioTurn(pcm16: Data(repeating: 0, count: 4800), startSeconds: 0, endSeconds: 1)); XCTFail() }
        catch { XCTAssertTrue(error is DatabaseError) }
        await transcriber.finish()
        XCTAssertTrue(results.snapshot.1.contains { $0.contains("12 audio segment(s)") })
        XCTAssertTrue(results.snapshot.0.isEmpty)
    }
}
