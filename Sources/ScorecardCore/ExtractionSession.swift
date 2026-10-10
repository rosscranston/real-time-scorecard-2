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
    public private(set) var configuration: ScorecardConfiguration
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
    private var generation = UUID()
    private let retryDelay: Duration
    public private(set) var pendingCount = 0
    public var bufferedJobCount: Int { pending.count }
    public static let maximumBufferedJobs = 128

    public init(company: CompanyScorecard, call: CallRecord, configuration: ScorecardConfiguration,
                database: ScorecardDatabase, extractor: any FactExtracting, retryDelay: Duration = .seconds(1)) throws {
        guard company.id == call.companyID, company.configurationID == configuration.id,
              call.configurationID == configuration.id else {
            throw DatabaseError(message: "Session identity does not match.")
        }
        self.company = company; self.call = call; self.configuration = configuration
        self.database = database; self.extractor = extractor
        self.retryDelay = retryDelay
        try database.saveConfiguration(configuration)
        try database.saveCompany(company); try database.saveCall(call)
        segments = try database.segments(callID: call.id, companyID: company.id)
        pendingCount = try database.pendingJobCount(companyID: company.id, callID: call.id, configurationID: configuration.id)
        pending = try database.pendingJobs(companyID: company.id, callID: call.id,
            configurationID: configuration.id, limit: Self.maximumBufferedJobs)
        // Recovery requires explicit resume; initialization does not send private audio/text.
    }
    public func resume() {
        errorMessage = nil
        guard worker == nil, pendingCount > 0 else { onChange?(); return }
        let current = generation
        worker = Task { [weak self] in await self?.drain(generation: current) }
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
            // Overflow stays durable on disk and is paged in after older work.
            if pendingCount == pending.count && pending.count < Self.maximumBufferedJobs { pending.append(job) }
            pendingCount += 1
            if errorMessage == nil { resume() }
        }
        onChange?()
    }
    public func mutate(_ mutation: (inout CompanyScorecard) throws -> [ChangeEvent]) throws {
        var next = company
        var events = try mutation(&next)
        events += NumericDeriver.recalculate(configuration: configuration, company: &next)
        try database.saveCompany(next, events: events)
        company = next; onChange?()
    }
    public func finish() throws {
        var ended = call; ended.endedAt = Date()
        try database.saveCall(ended); call = ended; onChange?()
    }
    public func switchConfiguration(_ configuration: ScorecardConfiguration) throws {
        guard configuration != self.configuration else { return }
        try database.saveConfiguration(configuration)
        var next = configuration.id == company.configurationID ? company
            : try database.company(id: company.id, configurationID: configuration.id)
                ?? CompanyScorecard(id: company.id, name: company.name, configuration: configuration)
        next.configurationRevision = configuration.revision
        next.latestSequence = max(next.latestSequence, company.latestSequence)
        var updatedCall = call; updatedCall.configurationID = configuration.id
        let jobs = segments.filter(\.isFinal).map {
            ExtractionJob(company: next, callID: call.id, configuration: configuration, segments: [$0])
        }
        let superseded = try database.pendingJobs(companyID: company.id, callID: call.id, configurationID: self.configuration.id)
        try database.switchConfiguration(company: next, call: updatedCall, superseded: superseded, pending: jobs)
        // Cancel only after the replacement state is durable. A late result from an
        // uncooperative transport cannot commit into the new configuration.
        generation = UUID(); worker?.cancel(); worker = nil; isProcessing = false
        self.configuration = configuration; company = next; call = updatedCall
        pending = Array(jobs.prefix(Self.maximumBufferedJobs)); pendingCount = jobs.count; errorMessage = nil
        onChange?(); resume()
    }
    public func waitUntilIdle() async {
        if let worker { await worker.value }
    }
    private func drain(generation currentGeneration: UUID) async {
        isProcessing = true; onChange?()
        defer {
            if generation == currentGeneration { isProcessing = false; worker = nil; onChange?() }
        }
        while pendingCount > 0 && !Task.isCancelled {
            if pending.isEmpty {
                do {
                    pending = try database.pendingJobs(companyID: company.id, callID: call.id,
                        configurationID: configuration.id, limit: Self.maximumBufferedJobs)
                    guard !pending.isEmpty else {
                        errorMessage = "Saved queue changed unexpectedly; reopen this call from History."; return
                    }
                } catch {
                    errorMessage = "Could not load saved transcript work; retry from History."; return
                }
            }
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
                guard generation == currentGeneration, !Task.isCancelled else { return }
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
                events += NumericDeriver.recalculate(configuration: configuration, company: &next)
                try database.saveCompany(next, events: events); company = next
                // A crash before these marks can replay, but reducer versions and same-value
                // detection make committed answers idempotent.
                for var item in batch { item.status = .completed; try database.saveJob(item) }
                pending.removeFirst(batch.count); pendingCount -= batch.count
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
                guard generation == currentGeneration, !Task.isCancelled else { return }
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
                var attempt = 0
                for var item in batch {
                    item.status = .failed; item.attempts += 1; item.errorSummary = message
                    attempt = max(attempt, item.attempts)
                    try? database.saveJob(item)
                    if let index = pending.firstIndex(where: { $0.id == item.id }) { pending[index] = item }
                }
                if Self.isTransient(error), attempt < 3, !Task.isCancelled {
                    // At most three paid attempts per durable job, including restarts.
                    // Authentication, quota and budget errors never enter this path.
                    do { try await Task.sleep(for: retryDelay * attempt) }
                    catch { return }
                    continue
                }
                errorMessage = message
                return
            }
        }
    }
    private static func isTransient(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        guard let error = error as? OpenAIError else { return false }
        switch error {
        case .network, .invalidResponse: return true
        case .server(let status): return (500...599).contains(status)
        default: return false
        }
    }
}
