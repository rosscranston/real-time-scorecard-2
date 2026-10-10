import XCTest
@testable import ScorecardCore

final class ScorecardCoreTests: XCTestCase {
    func configuration() -> ScorecardConfiguration {
        var software = FieldDefinition(key: "software", label: "Software", type: "select", options: ["Drake", "Lacerte", "Other"])
        software.sourcePolicy = "customer"
        software.aliases = ["Lacerte": ["La Certe"]]
        var returns = FieldDefinition(key: "returns", label: "Returns", type: "number")
        returns.min = 0; returns.max = 100_000; returns.integer = true
        return ScorecardConfiguration(id: "test", title: "Test", groups: [
            FieldGroup(id: "profile", label: "Profile", fields: [software, returns])
        ])
    }
    func fixture() -> (ScorecardConfiguration, CompanyScorecard, TranscriptEntry) {
        let config = configuration()
        let company = CompanyScorecard(name: "Example", configuration: config)
        let segment = TranscriptEntry(callID: UUID(), sequence: 1, speaker: .customer, text: "We use Drake.")
        return (config, company, segment)
    }
    func candidate(_ segment: TranscriptEntry, value: String = "Drake", confidence: Double = 0.96) -> FactCandidate {
        FactCandidate(fieldKey: "software", value: .string(value), confidence: confidence,
                      segmentID: segment.id, quote: segment.text)
    }
    func apply(_ candidate: FactCandidate, segment: TranscriptEntry, config: ScorecardConfiguration,
               company: inout CompanyScorecard, job: ExtractionJob? = nil) -> ApplyResult {
        let job = job ?? ExtractionJob(company: company, callID: segment.callID, configuration: config, segments: [segment])
        return FactReducer.apply(candidate, job: job, currentSegments: [segment.id: segment], configuration: config, company: &company)
    }

    func testSuppliedCatalogAndExportRoundTrip() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("configurations/company-scorecard.draft.json"))
        let config = try ScorecardConfiguration.load(data)
        XCTAssertEqual(config.fields.count, 41)
        XCTAssertEqual(config.fields.filter(\.isAutomatic).count, 33)
        XCTAssertEqual(try ScorecardConfiguration.load(ScorecardCoding.encoder().encode(config)), config)
        XCTAssertEqual(config.orderedGroups(for: "review").first?.id, "deal")
    }
    func testInvalidConfigurationFailsBeforeReplacingSavedVersion() throws {
        let database = try ScorecardDatabase(inMemory: true)
        var config = configuration()
        try database.saveConfiguration(config)
        config.groups[0].fields.append(config.fields[0])
        XCTAssertThrowsError(try database.saveConfiguration(config))
        XCTAssertEqual(try database.configurations().count, 1)
        config = configuration(); config.title = "Different"
        XCTAssertThrowsError(try database.saveConfiguration(config))
        config.revision += 1
        try database.saveConfiguration(config)
        XCTAssertEqual(try database.configurations().count, 2)
    }
    func testManualLocksProposalsAndAcceptanceRemainLocked() throws {
        var (config, company, segment) = fixture()
        try FactReducer.manualEdit(field: config.fields[0], text: "Lacerte", configuration: config, company: &company)
        let result = apply(candidate(segment), segment: segment, config: config, company: &company)
        XCTAssertEqual(result, .proposed)
        XCTAssertEqual(company.facts["software"]?.value, .string("Lacerte"))
        XCTAssertTrue(company.facts["software"]?.locked == true)
        XCTAssertNotNil(company.facts["software"]?.proposal)
        try FactReducer.acceptProposal(fieldKey: "software", configuration: config, company: &company)
        XCTAssertEqual(company.facts["software"]?.value, .string("Drake"))
        XCTAssertTrue(company.facts["software"]?.locked == true)
        try FactReducer.manualEdit(field: config.fields[0], text: "Lacerte", configuration: config, company: &company)
        XCTAssertEqual(company.facts["software"]?.value, .string("Lacerte"))
        XCTAssertTrue(company.facts["software"]?.locked == true)
        // Silence unused-mutation warnings while allowing the tuple's company to mutate.
        _ = (config, segment)
    }
    func testStaleResponseAfterEditAndUndoNeverRegainsValidity() throws {
        var (config, company, segment) = fixture()
        let job = ExtractionJob(company: company, callID: segment.callID, configuration: config, segments: [segment])
        try FactReducer.manualEdit(field: config.fields[0], text: "Lacerte", configuration: config, company: &company)
        _ = FactReducer.undo(configuration: config, company: &company)
        let result = apply(candidate(segment), segment: segment, config: config, company: &company, job: job)
        guard case .rejected = result else { return XCTFail("Stale job was accepted after undo.") }
        XCTAssertEqual(company.facts["software"]?.value, .null)
    }
    func testRevisionAndCompanyIsolation() {
        var (config, company, segment) = fixture()
        let job = ExtractionJob(company: company, callID: segment.callID, configuration: config, segments: [segment])
        var wrongCompany = CompanyScorecard(name: "Other", configuration: config)
        guard case .rejected = apply(candidate(segment), segment: segment, config: config, company: &wrongCompany, job: job) else {
            return XCTFail("Cross-company write.")
        }
        config.revision += 1; company.configurationRevision += 1
        guard case .rejected = apply(candidate(segment), segment: segment, config: config, company: &company, job: job) else {
            return XCTFail("Old configuration accepted.")
        }
        XCTAssertTrue(company.facts.isEmpty)
    }
    func testSpeakerPolicyAndDebriefOverride() {
        var (config, company, segment) = fixture()
        segment.speaker = .salesperson
        guard case .rejected = apply(candidate(segment), segment: segment, config: config, company: &company) else { return XCTFail() }
        segment.debrief = true
        XCTAssertEqual(apply(candidate(segment), segment: segment, config: config, company: &company), .updated)
    }
    func testEvidenceAndTranscriptionRevisionsAreChecked() {
        var (config, company, segment) = fixture()
        let oldJob = ExtractionJob(company: company, callID: segment.callID, configuration: config, segments: [segment])
        segment.revision += 1; segment.text = "We do not use Drake."
        guard case .rejected = apply(candidate(segment), segment: segment, config: config, company: &company, job: oldJob) else { return XCTFail() }
        var badQuote = candidate(segment); badQuote.quote = "Invented evidence"
        guard case .rejected = apply(badQuote, segment: segment, config: config, company: &company) else { return XCTFail() }
        XCTAssertTrue(company.facts.isEmpty)
    }
    func testClearingWaitsForNewEvidence() {
        var (config, company, segment) = fixture()
        XCTAssertEqual(apply(candidate(segment), segment: segment, config: config, company: &company), .updated)
        _ = FactReducer.clear(fieldKey: "software", configuration: config, company: &company)
        guard case .rejected = apply(candidate(segment), segment: segment, config: config, company: &company) else { return XCTFail() }
        segment.id = UUID(); segment.sequence = 2
        XCTAssertEqual(apply(candidate(segment), segment: segment, config: config, company: &company), .updated)
    }
    func testReplacementGateAndTentativeConfirmation() {
        var (config, company, segment) = fixture()
        XCTAssertEqual(apply(candidate(segment, confidence: 0.6), segment: segment, config: config, company: &company), .updated)
        segment.id = UUID(); segment.sequence = 2
        XCTAssertEqual(apply(candidate(segment, confidence: 0.98), segment: segment, config: config, company: &company), .updated)
        XCTAssertEqual(company.facts["software"]?.confidence, 0.98)
        segment.id = UUID(); segment.sequence = 3; segment.text = "We moved to Lacerte."
        guard case .rejected = apply(candidate(segment, value: "Lacerte", confidence: 0.8), segment: segment, config: config, company: &company) else { return XCTFail() }
        XCTAssertEqual(apply(candidate(segment, value: "Lacerte", confidence: 0.99), segment: segment, config: config, company: &company), .updated)
    }
    func testCollapsedCountCountsFieldsNotUpdatesAndNeverOpensSection() {
        var (config, company, segment) = fixture()
        FactReducer.setCollapsed(true, sectionID: "profile", company: &company)
        XCTAssertEqual(apply(candidate(segment), segment: segment, config: config, company: &company), .updated)
        segment.id = UUID(); segment.sequence = 2; segment.text = "We switched to Lacerte."
        XCTAssertEqual(apply(candidate(segment, value: "Lacerte"), segment: segment, config: config, company: &company), .updated)
        XCTAssertEqual(company.unreadFields["profile"]?.count, 1)
        XCTAssertTrue(company.collapsedSections.contains("profile"))
        FactReducer.setCollapsed(false, sectionID: "profile", company: &company)
        XCTAssertEqual(company.unreadFields["profile"]?.count, 0)
    }
    func testTypeValidationOtherAndRemovedOptionVisibility() throws {
        let config = configuration()
        XCTAssertThrowsError(try config.fields[1].validated(.number(-1)))
        XCTAssertThrowsError(try config.fields[1].validated(.number(1.5)))
        XCTAssertThrowsError(try config.fields[0].validated(.string("Invented")))
        XCTAssertThrowsError(try config.fields[0].validated(.string("Other")))
        XCTAssertEqual(try config.fields[0].validated(.string("La Certe")), .string("Lacerte"))
        var fact = FactRecord(); fact.value = .string("Removed")
        XCTAssertNil(FactReducer.displayedFact(fact, field: config.fields[0]))
        XCTAssertEqual(fact.value, .string("Removed"))
    }
    func testSQLiteRestartHistoryQueueAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite3")
        var (config, company, segment) = fixture()
        let call = CallRecord(id: segment.callID, company: company)
        let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
        do {
            let database = try ScorecardDatabase(url: url)
            let change = try FactReducer.manualEdit(field: config.fields[0], text: "Drake", configuration: config, company: &company)
            try database.saveCompany(company, events: [change])
            try database.saveConfiguration(config)
            try database.saveCall(call)
            XCTAssertTrue(try database.saveSegment(segment, companyID: company.id))
            XCTAssertFalse(try database.saveSegment(segment, companyID: company.id))
            try database.saveJob(job)
        }
        let reopened = try ScorecardDatabase(url: url)
        XCTAssertTrue(try reopened.company(id: company.id, configurationID: config.id)?.facts["software"]?.locked == true)
        XCTAssertEqual(try reopened.calls().count, 1)
        XCTAssertEqual(try reopened.segments(callID: call.id, companyID: company.id).count, 1)
        XCTAssertEqual(try reopened.pendingJobs().count, 1)
        XCTAssertEqual(try reopened.changes(companyID: company.id).count, 1)
        try reopened.deleteCompany(company.id)
        XCTAssertEqual(try reopened.companies().count, 0)
        XCTAssertEqual(try reopened.calls().count, 0)
        XCTAssertEqual(try reopened.pendingJobs().count, 0)
        XCTAssertEqual(try reopened.changes(companyID: company.id).count, 0)
        XCTAssertEqual(try reopened.configurations().count, 1)
    }
    func testDatabaseRollsBackMismatchedLedgerEvent() throws {
        let database = try ScorecardDatabase(inMemory: true)
        let (config, company, _) = fixture()
        let other = CompanyScorecard(name: "Other", configuration: config)
        let bad = ChangeEvent(company: other, fieldKey: "software", action: "bad", before: FactRecord(), after: FactRecord())
        XCTAssertThrowsError(try database.saveCompany(company, events: [bad]))
        XCTAssertTrue(try database.companies().isEmpty)
    }
}
