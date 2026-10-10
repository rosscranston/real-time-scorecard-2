import Foundation

public enum SpeakerRole: String, Codable, Sendable { case salesperson, customer }
public enum FactSource: String, Codable, Sendable { case call, calendar, email, manual, calculated }

public struct TranscriptEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var callID: UUID
    public var sequence: Int
    public var revision: Int
    public var speaker: SpeakerRole
    public var text: String
    public var seconds: Double
    public var isFinal: Bool
    public var debrief: Bool
    public var receivedAt: Date
    public var sentenceEndedAt: Date?
    public init(id: UUID = UUID(), callID: UUID, sequence: Int, revision: Int = 1,
                speaker: SpeakerRole, text: String, seconds: Double = 0,
                isFinal: Bool = true, debrief: Bool = false, sentenceEndedAt: Date? = nil) {
        self.id = id; self.callID = callID; self.sequence = sequence; self.revision = revision
        self.speaker = speaker; self.text = text; self.seconds = seconds; self.isFinal = isFinal
        self.debrief = debrief; self.receivedAt = Date(); self.sentenceEndedAt = sentenceEndedAt
    }
}

public struct Evidence: Codable, Equatable, Sendable {
    public var segmentID: UUID?
    public var segmentRevision: Int?
    public var callID: UUID?
    public var quote: String
    public var speaker: SpeakerRole?
    public var seconds: Double?
    public var sequence: Int
    public var source: FactSource
    public init(segment: TranscriptEntry, quote: String) {
        segmentID = segment.id; segmentRevision = segment.revision; callID = segment.callID
        self.quote = quote; speaker = segment.speaker; seconds = segment.seconds
        sequence = segment.sequence; source = .call
    }
    public init(quote: String, source: FactSource, sequence: Int = 0) {
        self.quote = quote; self.source = source; self.sequence = sequence
    }
}

public struct FactRecord: Codable, Equatable, Sendable {
    public var value: JSONValue = .null
    public var otherDetail: String?
    public var confidence: Double = 0
    public var estimated: Bool = false
    public var locked: Bool = false
    public var version: Int = 0
    public var evidence: [Evidence] = []
    public var proposal: FactProposal?
    public var dismissedProposalFingerprint: String?
    public var clearedThroughSequence: Int = -1
    public var updatedAt: Date = Date()
    public var derivedFrom: [String: Int]?
    public var display: String {
        if value == .string("Other"), let detail = otherDetail { return "Other: \(detail)" }
        return value.display
    }
    public var lastEvidenceSequence: Int { evidence.map(\.sequence).max() ?? -1 }
    public init() {}
}

public struct FactProposal: Codable, Equatable, Sendable {
    public var value: JSONValue
    public var otherDetail: String?
    public var confidence: Double
    public var estimated: Bool
    public var evidence: [Evidence]
    public var fingerprint: String {
        "\(value.display)|\(otherDetail ?? "")|\(evidence.map { "\($0.segmentID?.uuidString ?? ""):\($0.segmentRevision ?? 0):\($0.quote)" }.joined(separator: "|"))"
    }
    public init(value: JSONValue, otherDetail: String? = nil, confidence: Double,
                estimated: Bool = false, evidence: [Evidence]) {
        self.value = value; self.otherDetail = otherDetail; self.confidence = confidence
        self.estimated = estimated; self.evidence = evidence
    }
}

public struct FactCandidate: Sendable {
    public var fieldKey: String
    public var value: JSONValue
    public var otherDetail: String?
    public var confidence: Double
    public var estimated: Bool
    public var segmentID: UUID
    public var quote: String
    public var retractsPrevious: Bool
    public init(fieldKey: String, value: JSONValue, confidence: Double, segmentID: UUID,
                quote: String, otherDetail: String? = nil, estimated: Bool = false,
                retractsPrevious: Bool = false) {
        self.fieldKey = fieldKey; self.value = value; self.confidence = confidence
        self.segmentID = segmentID; self.quote = quote; self.otherDetail = otherDetail
        self.estimated = estimated; self.retractsPrevious = retractsPrevious
    }
}

public struct UndoEntry: Codable, Equatable, Sendable {
    public var fieldKey: String
    public var previous: FactRecord
}
public struct CompanyScorecard: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var domain: String?
    public var configurationID: String
    public var configurationRevision: Int
    public var facts: [String: FactRecord] = [:]
    public var collapsedSections: Set<String> = []
    public var unreadFields: [String: Set<String>] = [:]
    public var undoStack: [UndoEntry] = []
    public var latestSequence: Int = 0
    public init(id: UUID = UUID(), name: String, configuration: ScorecardConfiguration) {
        self.id = id; self.name = name; self.configurationID = configuration.id
        self.configurationRevision = configuration.revision
    }
    public var storageID: String { "\(id.uuidString):\(configurationID)" }
}

public struct CallRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var companyID: UUID
    public var companyName: String
    public var configurationID: String
    public var startedAt: Date
    public var endedAt: Date?
    public var callType: String
    public var isReplay: Bool
    public var calendarEventID: String?
    public var eventName: String?
    public var participantEmails: [String]
    public init(id: UUID = UUID(), company: CompanyScorecard, callType: String = "initial", isReplay: Bool = false) {
        self.id = id; companyID = company.id; companyName = company.name
        configurationID = company.configurationID; startedAt = Date()
        self.callType = callType; self.isReplay = isReplay; participantEmails = []
    }
}

public struct ExtractionJob: Codable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, running, failed, completed, blocked, superseded }
    public var id: UUID
    public var companyID: UUID
    public var callID: UUID
    public var configurationID: String
    public var configurationRevision: Int
    public var fieldVersions: [String: Int]
    public var segments: [TranscriptEntry]
    public var status: Status = .pending
    public var attempts: Int = 0
    public var createdAt: Date = Date()
    public var errorSummary: String?
    public var focusSequence: Int?
    public init(company: CompanyScorecard, callID: UUID, configuration: ScorecardConfiguration, segments: [TranscriptEntry]) {
        self.id = UUID(); self.companyID = company.id; self.callID = callID
        self.configurationID = configuration.id; self.configurationRevision = configuration.revision
        self.fieldVersions = Dictionary(uniqueKeysWithValues: configuration.fields.map { ($0.key, company.facts[$0.key]?.version ?? 0) })
        self.segments = segments
    }
}

public struct ChangeEvent: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var companyID: UUID
    public var configurationID: String
    public var fieldKey: String
    public var action: String
    public var before: FactRecord
    public var after: FactRecord
    public var date: Date = Date()
    public init(company: CompanyScorecard, fieldKey: String, action: String, before: FactRecord, after: FactRecord) {
        companyID = company.id; configurationID = company.configurationID
        self.fieldKey = fieldKey; self.action = action; self.before = before; self.after = after
    }
}
