import XCTest
@testable import ScorecardCore

private actor DelayedExtractor: FactExtracting {
    var started = false
    func hasStarted() -> Bool { started }
    func extract(job: ExtractionJob, company: CompanyScorecard, configuration: ScorecardConfiguration) async throws -> ExtractionResult {
        started = true
        try await Task.sleep(for: .milliseconds(80))
        let segment = job.segments.last!
        return ExtractionResult(candidates: [
            FactCandidate(fieldKey: "returns", value: .number(Double(segment.sequence) * 100),
                          confidence: 0.99, segmentID: segment.id, quote: segment.text)
        ], seconds: 0.08, warnings: [])
    }
}
private struct FailingExtractor: FactExtracting {
    func extract(job: ExtractionJob, company: CompanyScorecard, configuration: ScorecardConfiguration) async throws -> ExtractionResult {
        throw OpenAIError.quota
    }
}
private actor TransientExtractor: FactExtracting {
    var calls = 0
    let failures: Int
    init(failures: Int) { self.failures = failures }
    func count() -> Int { calls }
    func extract(job: ExtractionJob, company: CompanyScorecard, configuration: ScorecardConfiguration) async throws -> ExtractionResult {
        calls += 1
        if calls <= failures { throw OpenAIError.invalidResponse }
        return ExtractionResult(candidates: [], seconds: 0, warnings: [])
    }
}
private actor SwitchExtractor: FactExtracting {
    var oldStarted = false
    func hasStarted() -> Bool { oldStarted }
    func extract(job: ExtractionJob, company: CompanyScorecard, configuration: ScorecardConfiguration) async throws -> ExtractionResult {
        if configuration.revision == 1 {
            oldStarted = true
            // Deliberately ignore cancellation to represent an already returning HTTP response.
            try? await Task.sleep(for: .milliseconds(80))
        }
        let segment = job.segments.last!
        let key = configuration.revision == 1 ? "returns" : "team"
        return ExtractionResult(candidates: [FactCandidate(fieldKey: key, value: .number(configuration.revision == 1 ? 999 : 8),
            confidence: 0.99, segmentID: segment.id, quote: segment.text)], seconds: 0, warnings: [])
    }
}

private actor SequenceExtractor: FactExtracting {
    var observed: [Int] = []
    func sequences() -> [Int] { observed }
    func extract(job: ExtractionJob, company: CompanyScorecard, configuration: ScorecardConfiguration) async throws -> ExtractionResult {
        observed += job.segments.filter { $0.sequence >= (job.focusSequence ?? 0) }.map(\.sequence)
        return ExtractionResult(candidates: [], seconds: 0, warnings: [])
    }
}

final class ExtractionSessionTests: XCTestCase {
    @MainActor func testLargeOfflineQueueRestartsInTranscriptOrderWithoutLosingOverflow() async throws {
        let config = ScorecardConfiguration(id: "offline", title: "Offline", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "returns", label: "Returns", type: "number")])
        ])
        let company = CompanyScorecard(name: "Offline firm", configuration: config)
        let call = CallRecord(company: company)
        let db = try ScorecardDatabase(inMemory: true)
        let first = try ExtractionSession(company: company, call: call, configuration: config, database: db, extractor: FailingExtractor())
        try first.ingest(TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "First sentence."))
        await first.waitUntilIdle()
        for sequence in 2...300 {
            try first.ingest(TranscriptEntry(callID: call.id, sequence: sequence, speaker: .customer, text: "Sentence \(sequence)."))
        }
        XCTAssertEqual(first.pendingCount, 300)
        XCTAssertEqual(first.bufferedJobCount, ExtractionSession.maximumBufferedJobs)
        XCTAssertEqual(try db.pendingJobCount(companyID: company.id, callID: call.id, configurationID: config.id), 300)
        let extractor = SequenceExtractor()
        let restored = try ExtractionSession(company: first.company, call: call, configuration: config, database: db, extractor: extractor)
        XCTAssertEqual(restored.bufferedJobCount, ExtractionSession.maximumBufferedJobs)
        restored.resume(); await restored.waitUntilIdle()
        let processed = await extractor.sequences()
        XCTAssertEqual(processed, Array(1...300))
        XCTAssertEqual(restored.pendingCount, 0)
        XCTAssertTrue(try db.pendingJobs().isEmpty)
        XCTAssertEqual(restored.measurements.count, 300)
        XCTAssertNil(restored.errorMessage)
    }
    @MainActor func testConfigurationSwitchSupersedesDiskOverflowAsWellAsMemoryPage() async throws {
        let config = ScorecardConfiguration(id: "overflow", title: "Overflow", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "returns", label: "Returns", type: "number")])
        ])
        let company = CompanyScorecard(name: "Switch firm", configuration: config)
        let call = CallRecord(company: company)
        let db = try ScorecardDatabase(inMemory: true)
        let session = try ExtractionSession(company: company, call: call, configuration: config, database: db, extractor: FailingExtractor())
        try session.ingest(TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "First sentence."))
        await session.waitUntilIdle()
        for sequence in 2...140 {
            try session.ingest(TranscriptEntry(callID: call.id, sequence: sequence, speaker: .customer, text: "Sentence \(sequence)."))
        }
        var updated = config; updated.revision = 2
        try session.switchConfiguration(updated)
        await session.waitUntilIdle()
        let jobs = try db.pendingJobs(companyID: company.id, callID: call.id)
        XCTAssertEqual(jobs.count, 140)
        XCTAssertTrue(jobs.allSatisfy { $0.configurationRevision == 2 })
        XCTAssertEqual(session.bufferedJobCount, ExtractionSession.maximumBufferedJobs)
    }
    @MainActor func testConfigurationSwitchRejectsOldInflightResponseAndKeepsRemovedFacts() async throws {
        let config = ScorecardConfiguration(id: "test", title: "Test", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "returns", label: "Returns", type: "number")])
        ])
        var company = CompanyScorecard(name: "Test", configuration: config)
        var old = FactRecord(); old.value = .number(200); company.facts["returns"] = old
        let call = CallRecord(company: company)
        let db = try ScorecardDatabase(inMemory: true)
        let extractor = SwitchExtractor()
        let session = try ExtractionSession(company: company, call: call, configuration: config, database: db, extractor: extractor)
        try session.ingest(TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "We have eight people."))
        while !(await extractor.hasStarted()) { await Task.yield() }
        var updated = config; updated.revision = 2
        updated.groups[0].fields = [FieldDefinition(key: "team", label: "Team", type: "number")]
        try session.switchConfiguration(updated)
        await session.waitUntilIdle()
        XCTAssertEqual(session.company.facts["returns"]?.value, .number(200))
        XCTAssertEqual(session.company.facts["team"]?.value, .number(8))
        XCTAssertEqual(session.configuration.revision, 2)
        XCTAssertTrue(try db.pendingJobs().isEmpty)
        XCTAssertEqual(try db.configurations().count, 2)
        let job = ExtractionJob(company: session.company, callID: call.id, configuration: updated, segments: [])
        let context = ExtractionRequests.context(job: job, company: session.company, configuration: updated)
        XCTAssertFalse(context.contains("returns:"))
        XCTAssertTrue(context.contains("team: 8"))
    }
    @MainActor func testTransientRetryRecoversAndExhaustionSurvivesRestart() async throws {
        let config = ScorecardConfiguration(id: "test", title: "Test", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "returns", label: "Returns", type: "number")])
        ])
        for failures in [1, 10] {
            let company = CompanyScorecard(name: "Test", configuration: config)
            let call = CallRecord(company: company)
            let db = try ScorecardDatabase(inMemory: true)
            let extractor = TransientExtractor(failures: failures)
            let session = try ExtractionSession(company: company, call: call, configuration: config,
                database: db, extractor: extractor, retryDelay: .milliseconds(1))
            try session.ingest(TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "100 returns."))
            await session.waitUntilIdle()
            let attempts = await extractor.count()
            XCTAssertEqual(attempts, failures == 1 ? 2 : 3)
            XCTAssertEqual(session.pendingCount, failures == 1 ? 0 : 1)
            if failures > 3 {
                XCTAssertEqual(try db.pendingJobs().first?.attempts, 3)
                let restored = try ExtractionSession(company: session.company, call: call, configuration: config,
                    database: db, extractor: extractor, retryDelay: .milliseconds(1))
                XCTAssertFalse(restored.isProcessing)
                restored.resume()
                await restored.waitUntilIdle()
                let afterExplicitRetry = await extractor.count()
                XCTAssertEqual(afterExplicitRetry, 4, "An explicit retry permits one attempt; exhausted work does not start another automatic loop.")
            } else { XCTAssertNil(session.errorMessage) }
        }
    }
    @MainActor func testArrivalsContinueAndManualEditSurvivesInflightResult() async throws {
        let config = ScorecardConfiguration(id: "test", title: "Test", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "returns", label: "Returns", type: "number")])
        ])
        let company = CompanyScorecard(name: "Test", configuration: config)
        let call = CallRecord(company: company)
        let db = try ScorecardDatabase(inMemory: true)
        let extractor = DelayedExtractor()
        let session = try ExtractionSession(company: company, call: call, configuration: config, database: db, extractor: extractor)
        try session.ingest(TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "100 returns."))
        while !(await extractor.hasStarted()) { await Task.yield() }
        try session.mutate { state in
            [try FactReducer.manualEdit(field: config.fields[0], text: "999", configuration: config, company: &state)]
        }
        try session.ingest(TranscriptEntry(callID: call.id, sequence: 2, speaker: .customer, text: "Actually 200 returns."))
        XCTAssertEqual(session.segments.count, 2)
        XCTAssertEqual(session.pendingCount, 2)
        await session.waitUntilIdle()
        XCTAssertEqual(session.company.facts["returns"]?.value, .number(999))
        XCTAssertEqual(session.company.facts["returns"]?.proposal?.value, .number(200))
        XCTAssertTrue(session.company.facts["returns"]?.locked == true)
        XCTAssertTrue(try db.pendingJobs().isEmpty)
        XCTAssertEqual(session.measurements.count, 2)
    }
    @MainActor func testQuotaFailurePersistsQueueAndStopsAutomaticRetries() async throws {
        let config = ScorecardConfiguration(id: "test", title: "Test", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "returns", label: "Returns", type: "number")])
        ])
        let company = CompanyScorecard(name: "Test", configuration: config)
        let call = CallRecord(company: company)
        let db = try ScorecardDatabase(inMemory: true)
        let session = try ExtractionSession(company: company, call: call, configuration: config, database: db, extractor: FailingExtractor())
        let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "100 returns.")
        try session.ingest(segment); await session.waitUntilIdle()
        XCTAssertNotNil(session.errorMessage)
        try session.ingest(segment) // duplicate isn't queued
        try session.ingest(TranscriptEntry(callID: call.id, sequence: 2, speaker: .customer, text: "200 returns."))
        XCTAssertEqual(session.pendingCount, 2)
        XCTAssertFalse(session.isProcessing)
        XCTAssertEqual(try db.pendingJobs().count, 2)
        XCTAssertEqual(try db.segments(callID: call.id, companyID: company.id).count, 2)
    }
}
