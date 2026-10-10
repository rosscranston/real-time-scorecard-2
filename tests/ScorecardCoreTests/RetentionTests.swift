import XCTest
@testable import ScorecardCore

final class RetentionTests: XCTestCase {
    func testRetentionRemovesRawPayloadsButKeepsFactsAndPendingCalls() throws {
        let config = ScorecardConfiguration(id: "test", title: "Test", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [FieldDefinition(key: "software", label: "Software", type: "string")])
        ])
        let db = try ScorecardDatabase(inMemory: true)
        var company = CompanyScorecard(name: "Synthetic", configuration: config)
        let old = Date().addingTimeInterval(-40 * 86400)
        var finished = CallRecord(company: company); finished.startedAt = old; finished.endedAt = old
        var pending = CallRecord(company: company); pending.startedAt = old; pending.endedAt = old
        try db.saveCompany(company); try db.saveCall(finished); try db.saveCall(pending)
        let first = TranscriptEntry(callID: finished.id, sequence: 1, speaker: .customer, text: "Drake.")
        let second = TranscriptEntry(callID: pending.id, sequence: 2, speaker: .customer, text: "Lacerte.")
        try db.saveSegment(first, companyID: company.id); try db.saveSegment(second, companyID: company.id)
        var completedJob = ExtractionJob(company: company, callID: finished.id, configuration: config, segments: [first])
        completedJob.status = .completed
        try db.saveJob(completedJob)
        try db.saveJob(ExtractionJob(company: company, callID: pending.id, configuration: config, segments: [second]))
        var fact = FactRecord(); fact.value = .string("Drake"); fact.evidence = [Evidence(segment: first, quote: "Drake.")]
        company.facts["software"] = fact; try db.saveCompany(company)
        XCTAssertEqual(try db.pruneTranscripts(olderThan: Date().addingTimeInterval(-30 * 86400)), 1)
        XCTAssertTrue(try db.segments(callID: finished.id, companyID: company.id).isEmpty)
        XCTAssertEqual(try db.segments(callID: pending.id, companyID: company.id).count, 1)
        XCTAssertEqual(try db.pendingJobs().count, 1)
        XCTAssertEqual(try db.calls().count, 2)
        XCTAssertEqual(try db.company(id: company.id, configurationID: config.id)?.facts["software"]?.evidence.first?.quote, "Drake.")
        XCTAssertEqual(try db.pruneTranscripts(olderThan: Date()), 0)
        try db.deleteCompany(company.id)
        XCTAssertTrue(try db.calls().isEmpty)
        XCTAssertTrue(try db.pendingJobs().isEmpty)
        XCTAssertTrue(try db.companies().isEmpty)
    }
}
