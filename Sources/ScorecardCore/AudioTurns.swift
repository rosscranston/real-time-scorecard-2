import Foundation

public struct AudioTurn: Sendable, Equatable {
    public var id: UUID = UUID()
    public var pcm16: Data
    public var startSeconds: Double
    public var endSeconds: Double
    public init(id: UUID = UUID(), pcm16: Data, startSeconds: Double, endSeconds: Double) {
        self.id = id; self.pcm16 = pcm16; self.startSeconds = startSeconds; self.endSeconds = endSeconds
    }
}

/// Small energy-based turn detector operating on mono PCM16 at 24 kHz.
/// It bounds uninterrupted speech chunks and retains a short leading pad.
/// Thresholds are configurable because microphone noise varies by device.
public struct SpeechTurnBuffer: Sendable {
    public var silenceSeconds: Double = 0.55
    public var maxTurnSeconds: Double = 3
    public var minimumSpeechSeconds: Double = 0.10
    public var threshold: Double = 0.006
    private var prefix = Data()
    private var current = Data()
    private var start: Double = 0
    private var lastVoiceEnd: Double = 0
    private var speechDuration: Double = 0
    private var quietDuration: Double = 0
    private let bytesPerSecond: Double = 48_000
    public init() {}
    public mutating func ingest(_ data: Data, startSeconds: Double) -> AudioTurn? {
        guard !data.isEmpty, data.count % 2 == 0, startSeconds.isFinite else { return nil }
        let duration = Double(data.count) / bytesPerSecond
        let voiced = Self.rms(data) >= threshold
        if current.isEmpty {
            guard voiced else {
                prefix.append(data)
                if prefix.count > 14_400 { prefix.removeFirst(prefix.count - 14_400) }
                return nil
            }
            start = max(0, startSeconds - Double(prefix.count) / bytesPerSecond)
            current = prefix; prefix.removeAll(keepingCapacity: true)
        }
        current.append(data)
        if voiced { speechDuration += duration; quietDuration = 0; lastVoiceEnd = startSeconds + duration }
        else { quietDuration += duration }
        guard quietDuration >= silenceSeconds || Double(current.count) / bytesPerSecond >= maxTurnSeconds else { return nil }
        return flush()
    }
    public mutating func flush() -> AudioTurn? {
        defer { current.removeAll(keepingCapacity: true); speechDuration = 0; quietDuration = 0 }
        guard speechDuration >= minimumSpeechSeconds, !current.isEmpty else { return nil }
        return AudioTurn(pcm16: current, startSeconds: start, endSeconds: lastVoiceEnd)
    }
    public static func rms(_ data: Data) -> Double {
        guard data.count >= 2 else { return 0 }
        var sum = 0.0
        data.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: data.count - 1, by: 2) {
                let sample = Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))) / 32768
                sum += sample * sample
            }
        }
        return sqrt(sum / Double(data.count / 2))
    }
}

public struct AudioTranscriptEvent: Sendable {
    public var id: UUID
    public var role: SpeakerRole
    public var text: String
    public var startSeconds: Double
    public var sentenceEndedAt: Date
    public init(id: UUID, role: SpeakerRole, text: String, startSeconds: Double, sentenceEndedAt: Date) {
        self.id = id; self.role = role; self.text = text; self.startSeconds = startSeconds; self.sentenceEndedAt = sentenceEndedAt
    }
}

/// Provider completions can arrive out of order. Bind provider item IDs on commit
/// acknowledgement and retain each original client ID and audio timestamp.
public struct AudioCommitTracker: Sendable {
    private var waiting: [AudioTurn] = []
    private var mapped: [String: AudioTurn] = [:]
    private var completed: Set<String> = []
    public init() {}
    public var pendingCount: Int { waiting.count + mapped.count }
    public mutating func enqueue(_ turn: AudioTurn) { waiting.append(turn) }
    public mutating func acknowledged(itemID: String) -> Bool {
        guard !itemID.isEmpty, !waiting.isEmpty, mapped[itemID] == nil, !completed.contains(itemID) else { return false }
        mapped[itemID] = waiting.removeFirst()
        return true
    }
    public mutating func finish(itemID: String) -> AudioTurn? {
        guard let turn = mapped.removeValue(forKey: itemID), completed.insert(itemID).inserted else { return nil }
        // Session lifetime is bounded; keep deduplication memory bounded too.
        if completed.count > 10_000 { completed.removeAll(); completed.insert(itemID) }
        return turn
    }
}
