import Foundation

public protocol FactExtracting: Sendable {
    func extract(job: ExtractionJob, company: CompanyScorecard, configuration: ScorecardConfiguration) async throws -> ExtractionResult
}
extension CloudExtractor: FactExtracting {}

public struct ProcessingMeasurement: Codable, Sendable {
    public var sequence: Int
    public var queueSeconds: Double
    public var processingSeconds: Double
    public var totalSeconds: Double
    public var updates: Int
    public var warnings: [String]
}

/// One serial commit lane per active call. Input continues arriving while the
/// network is suspended; manual edits share the same main-actor commit lane.
@MainActor
public final class ExtractionSession {
    public private(set) var company: CompanyScorecard
    public let configuration: ScorecardConfiguration
    public private(set) var call: CallRecord
    public private(set) var segments: [TranscriptEntry]
    public private(set) var measurements: [ProcessingMeasurement] = []
    public private(set) var errorMessage: String?
    public private(set) var isProcessing = false
    public var onChange: (() -> Void)?
    public var onMeasurement: ((ProcessingMeasurement) -> Void)?
    private let database: ScorecardDatabase
    private let extractor: any FactExtracting
    private var pending: [ExtractionJob] = []
    private var worker: Task<Void, Never>?
    public var pendingCount: Int { pending.count }

    public init(company: CompanyScorecard, call: CallRecord, configuration: ScorecardConfiguration,
                database: ScorecardDatabase, extractor: any FactExtracting) throws {
        guard company.id == call.companyID, company.configurationID == configuration.id,
              call.configurationID == configuration.id else {
            throw DatabaseError(message: "Session identity does not match.")
        }
        self.company = company; self.call = call; self.configuration = configuration
        self.database = database; self.extractor = extractor
        try database.saveConfiguration(configuration)
        try database.saveCompany(company); try database.saveCall(call)
        segments = try database.segments(callID: call.id, companyID: company.id)
        pending = try database.pendingJobs().filter {
            $0.companyID == company.id && $0.callID == call.id && $0.configurationID == configuration.id
        }
        // Recovery requires explicit resume; initialization does not send private audio/text.
    }
    public func resume() {
        errorMessage = nil
        guard worker == nil, !pending.isEmpty else { onChange?(); return }
        worker = Task { [weak self] in await self?.drain() }
    }
    public func ingest(_ segment: TranscriptEntry) throws {
        guard segment.callID == call.id else { throw DatabaseError(message: "Wrong call for transcript.") }
        var next = company; next.latestSequence = max(next.latestSequence, segment.sequence)
        let job = segment.isFinal ? ExtractionJob(company: next, callID: call.id, configuration: configuration, segments: [segment]) : nil
        guard try database.saveIncoming(segment, company: next, job: job) else { return }
        company = next
        segments.removeAll { $0.id == segment.id }; segments.append(segment)
        segments.sort { $0.sequence < $1.sequence }
        if let job {
            pending.append(job)
            if errorMessage == nil { resume() }
        }
        onChange?()
    }
    public func mutate(_ mutation: (inout CompanyScorecard) throws -> [ChangeEvent]) throws {
        var next = company
        let events = try mutation(&next)
        try database.saveCompany(next, events: events)
        company = next; onChange?()
    }
    public func finish() throws {
        var ended = call; ended.endedAt = Date()
        try database.saveCall(ended); call = ended; onChange?()
    }
    public func waitUntilIdle() async {
        if let worker { await worker.value }
    }
    private func drain() async {
        isProcessing = true; onChange?()
        defer { isProcessing = false; worker = nil; onChange?() }
        while !pending.isEmpty && !Task.isCancelled {
            // Coalesce bursts, but cap each request's new evidence.
            let batch = Array(pending.prefix(4))
            let ids = Set(batch.flatMap(\.segments).map(\.id))
            let fresh = segments.filter { ids.contains($0.id) && $0.isFinal }
            guard let first = fresh.map(\.sequence).min() else {
                errorMessage = "Pending work has no final transcript."; return
            }
            let context = Array(segments.filter { $0.isFinal && $0.sequence < first }.suffix(12))
            var job = ExtractionJob(company: company, callID: call.id, configuration: configuration, segments: context + fresh)
            job.focusSequence = first; job.status = .running
            let started = Date()
            do {
                // The durable per-segment jobs remain the recovery source until commit.
                let result = try await extractor.extract(job: job, company: company, configuration: configuration)
                var next = company
                var events: [ChangeEvent] = []
                var warnings = result.warnings
                let current = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
                for candidate in result.candidates {
                    let before = next.facts[candidate.fieldKey] ?? FactRecord()
                    let applied = FactReducer.apply(candidate, job: job, currentSegments: current,
                                                    configuration: configuration, company: &next)
                    switch applied {
                    case .updated, .proposed:
                        events.append(ChangeEvent(company: next, fieldKey: candidate.fieldKey,
                                                  action: applied == .updated ? "extracted" : "proposed",
                                                  before: before, after: next.facts[candidate.fieldKey]!))
                    case .rejected(let reason): warnings.append("\(candidate.fieldKey): \(reason)")
                    case .unchanged: break
                    }
                }
                try database.saveCompany(next, events: events); company = next
                // A crash before these marks can replay, but reducer versions and same-value
                // detection make committed answers idempotent.
                for var item in batch { item.status = .completed; try database.saveJob(item) }
                pending.removeFirst(batch.count)
                let completed = Date()
                for segment in fresh {
                    let end = segment.sentenceEndedAt ?? segment.receivedAt
                    let measurement = ProcessingMeasurement(sequence: segment.sequence,
                        queueSeconds: max(0, started.timeIntervalSince(segment.receivedAt)),
                        processingSeconds: completed.timeIntervalSince(started),
                        totalSeconds: completed.timeIntervalSince(end), updates: events.count, warnings: warnings)
                    measurements.append(measurement); onMeasurement?(measurement)
                }
                onChange?()
            } catch {
                let message: String
                if let error = error as? OpenAIError { message = error.localizedDescription }
                else if let error = error as? ConfigurationError { message = error.localizedDescription }
                else if let error = error as? DecodingError {
                    let context: DecodingError.Context
                    switch error {
                    case .dataCorrupted(let value), .keyNotFound(_, let value),
                         .typeMismatch(_, let value), .valueNotFound(_, let value): context = value
                    @unknown default: context = .init(codingPath: [], debugDescription: "")
                    }
                    // Schema paths contain no transcript or provider error-body text.
                    message = "Response decoding failed at \(context.codingPath.map(\.stringValue).joined(separator: ".")); work is saved."
                } else { message = "Processing could not finish; transcript work is saved." }
                errorMessage = message
                for var item in batch {
                    item.status = .failed; item.attempts += 1; item.errorSummary = message
                    try? database.saveJob(item)
                }
                // Explicit retry avoids unattended quota/rate-limit loops.
                return
            }
        }
    }
}
