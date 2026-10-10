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

final class ExtractionSessionTests: XCTestCase {
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
