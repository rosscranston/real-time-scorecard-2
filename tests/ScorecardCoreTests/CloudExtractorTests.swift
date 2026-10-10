import XCTest
@testable import ScorecardCore

private actor MockTransport: HTTPTransport {
    var count = 0
    let status: Int
    let payload: Data
    init(status: Int, payload: String) { self.status = status; self.payload = Data(payload.utf8) }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private struct InterruptedTransport: HTTPTransport {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(code) }
}

private actor NumericScopeTransport: HTTPTransport {
    let response: Data
    let supported: Bool
    var checks = 0
    init(response: Data, supported: Bool) { self.response = response; self.supported = supported }
    func count() -> Int { checks }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        if request.url!.lastPathComponent == "responses" { data = response }
        else {
            checks += 1
            data = try JSONSerialization.data(withJSONObject: ["answers": [["type": "choice", "name": "returns", "choice": supported ? "supported" : "__unknown__", "confidence": 0.99]]])
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor FocusedReviewTransport: HTTPTransport {
    let responses: Data
    let reviewChoice: String
    var decisionCalls = 0
    var focusedQuestions = 0
    init(responses: Data, reviewChoice: String) { self.responses = responses; self.reviewChoice = reviewChoice }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        if request.url!.lastPathComponent == "responses" { data = responses }
        else {
            decisionCalls += 1
            if decisionCalls == 2 {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                focusedQuestions = (body["questions"] as! [[String: Any]]).count
            }
            let choice = decisionCalls == 1 ? "Lacerte" : reviewChoice
            data = try JSONSerialization.data(withJSONObject: ["answers": [["type": "choice", "name": "software", "choice": choice, "confidence": 0.99]]])
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class CloudExtractorTests: XCTestCase {
    func testFocusedNumericGateRunsOnceAndNeverSendsFabricatedEvidenceForReview() async throws {
        var field = FieldDefinition(key: "returns", label: "Annual returns", type: "number")
        field.requiresEvidenceGate = true
        let config = ScorecardConfiguration(id: "scope", title: "Scope", groups: [FieldGroup(id: "profile", label: "Profile", fields: [field])])
        let company = CompanyScorecard(name: "Synthetic", configuration: config)
        let call = CallRecord(company: company)
        let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "Our annual volume is 1280 returns.")
        let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
        for (supported, quote) in [(false, segment.text), (true, segment.text), (true, "Invented quote")] {
            let facts: [String: Any] = ["facts": [["field_key": "returns", "value": 1280, "confidence": 0.99,
                "estimated": false, "segment_id": segment.id.uuidString, "quote": quote, "retracts_previous": false]]]
            let text = String(decoding: try JSONSerialization.data(withJSONObject: facts), as: UTF8.self)
            let response = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [["type": "output_text", "text": text]]]]])
            let transport = NumericScopeTransport(response: response, supported: supported)
            let client = try OpenAIClient(key: "fake-test-key", transport: transport)
            let result = try await CloudExtractor(client: client).extract(job: job, company: company, configuration: config)
            let checks = await transport.count()
            XCTAssertEqual(checks, quote == segment.text ? 1 : 0)
            XCTAssertEqual(result.candidates.count, supported && quote == segment.text ? 1 : 0)
            XCTAssertTrue(result.reviewCandidates.isEmpty)
        }
    }
    func testNumericScopeGateRejectsSampleAndRequiresConfidentReplacement() throws {
        var field = FieldDefinition(key: "returns", label: "Annual firm returns", type: "number")
        field.requiresEvidenceGate = true
        field.evidenceRule = "Whole-firm annual volume, excluding evaluation samples."
        let config = ScorecardConfiguration(id: "scope", title: "Scope", groups: [FieldGroup(id: "profile", label: "Profile", fields: [field])])
        let roundtrip = try ScorecardConfiguration.load(ScorecardCoding.encoder().encode(config))
        XCTAssertEqual(roundtrip.fields.first?.requiresEvidenceGate, true)
        var company = CompanyScorecard(name: "Synthetic firm", configuration: config)
        let call = CallRecord(company: company)
        _ = try FactReducer.manualEdit(field: field, text: "1260", configuration: config, company: &company)
        _ = FactReducer.toggleLock(fieldKey: field.key, company: &company)
        let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "Our evaluation will use twelve returns.")
        let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
        let facts: [String: Any] = ["facts": [["field_key": "returns", "value": 12, "confidence": 0.99,
            "estimated": false, "segment_id": segment.id.uuidString, "quote": segment.text, "retracts_previous": false]]]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: facts), as: UTF8.self)
        let response = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [["type": "output_text", "text": payload]]]]])
        for choice in ["__unknown__", "unexpected", "supported"] {
            let data = try JSONSerialization.data(withJSONObject: ["answers": [["type": "choice", "name": "returns", "choice": choice, "confidence": 0.8]]])
            let result = try CloudExtractor.decode(decisions: data, responses: response, configuration: config, seconds: 0)
            XCTAssertTrue(result.reviewCandidates.isEmpty, "Scope rejection must not enter the option recheck path")
            if choice == "supported" {
                XCTAssertEqual(result.candidates.first?.confidence, 0.8)
                var unchanged = company
                XCTAssertEqual(FactReducer.apply(result.candidates[0], job: job, currentSegments: [segment.id: segment], configuration: config, company: &unchanged), .rejected("Replacement needs stronger evidence."))
                XCTAssertEqual(unchanged.facts["returns"]?.value, .number(1260))
            } else { XCTAssertTrue(result.candidates.isEmpty) }
        }
        let missing = try CloudExtractor.decode(decisions: nil, responses: response, configuration: config, seconds: 0)
        XCTAssertTrue(missing.candidates.isEmpty)
    }
    func testTransportFailuresRetainReservationsAndCancellationIsNotRetryableNetworkFailure() async throws {
        for code in [URLError.Code.timedOut, .cancelled] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("scorecard-usage-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: url) }
            let client = try OpenAIClient(key: "fake-test-key", transport: InterruptedTransport(code: code), ledgerURL: url)
            do { _ = try await client.post(endpoint: "responses", body: Data("{}".utf8)); XCTFail("Expected interruption") }
            catch is CancellationError { XCTAssertEqual(code, .cancelled) }
            catch let error as OpenAIError { XCTAssertEqual(code, .timedOut); XCTAssertEqual(error, .network) }
            let usage = await client.usage()
            XCTAssertGreaterThan(usage.chargedOrReservedUSD, 0)
            XCTAssertEqual(usage.requests.count, 1)
            XCTAssertEqual(usage.requests[0].estimatedUSD, usage.chargedOrReservedUSD)
            XCTAssertEqual(usage.requests[0].endpoint, code == .cancelled ? "responses_cancelled" : "responses_transport_failure")
            let reopened = try OpenAIClient(key: "fake-test-key", ledgerURL: url)
            let persisted = await reopened.usage()
            XCTAssertEqual(persisted.chargedOrReservedUSD, usage.chargedOrReservedUSD)
            let stored = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(stored.contains("fake-test-key"))
        }
    }
    func config() -> ScorecardConfiguration {
        ScorecardConfiguration(id: "test", title: "Test", groups: [FieldGroup(id: "profile", label: "Profile", fields: [
            FieldDefinition(key: "software", label: "Software", type: "select", options: ["Drake", "Lacerte"])
        ])])
    }
    func response(value: String, id: UUID) throws -> Data {
        let facts: [String: Any] = ["facts": [[
            "field_key": "software", "value": value, "other_detail": NSNull(), "confidence": 0.96,
            "estimated": false, "segment_id": id.uuidString, "quote": "We use Drake.", "retracts_previous": false
        ]]]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: facts), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [["type": "output_text", "text": text]]]]])
    }
    func testFocusedReviewIsBoundedAndStillRequiresAgreement() async throws {
        for choice in ["Drake", "Lacerte"] {
            let config = config(); let company = CompanyScorecard(name: "Synthetic", configuration: config)
            let call = CallRecord(company: company)
            let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "We use Drake.")
            let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
            let transport = FocusedReviewTransport(responses: try response(value: "Drake", id: segment.id), reviewChoice: choice)
            let client = try OpenAIClient(key: "fake-test-key", transport: transport)
            let result = try await CloudExtractor(client: client).extract(job: job, company: company, configuration: config)
            let count = await transport.decisionCalls
            let questions = await transport.focusedQuestions
            XCTAssertEqual(count, 2); XCTAssertEqual(questions, 1)
            XCTAssertEqual(result.candidates.count, choice == "Drake" ? 1 : 0)
            if let candidate = result.candidates.first {
                var current = company
                XCTAssertEqual(FactReducer.apply(candidate, job: job, currentSegments: [segment.id: segment], configuration: config, company: &current), .updated)
                XCTAssertEqual(current.facts["software"]?.value, .string("Drake"))
            }
        }
    }
    func testFocusedReviewNeverRetriesFabricatedEvidence() async throws {
        let config = config(); let company = CompanyScorecard(name: "Synthetic", configuration: config)
        let call = CallRecord(company: company)
        let segment = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer, text: "We have not chosen software.")
        let job = ExtractionJob(company: company, callID: call.id, configuration: config, segments: [segment])
        let transport = FocusedReviewTransport(responses: try response(value: "Drake", id: segment.id), reviewChoice: "Drake")
        let client = try OpenAIClient(key: "fake-test-key", transport: transport)
        let result = try await CloudExtractor(client: client).extract(job: job, company: company, configuration: config)
        let count = await transport.decisionCalls
        XCTAssertEqual(count, 1); XCTAssertTrue(result.candidates.isEmpty)
    }
    func testModelDisagreementDoesNotProduceCandidate() throws {
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Lacerte","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: response(value: "Drake", id: UUID()), configuration: config())
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
    }
    func testRepeatedCompleteOutputTextIsDecodedOnce() throws {
        var object = try JSONSerialization.jsonObject(with: response(value: "Drake", id: UUID())) as! [String: Any]
        var output = object["output"] as! [[String: Any]]
        let content = output[0]["content"] as! [[String: Any]]
        output[0]["content"] = content + content; object["output"] = output
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Drake","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: JSONSerialization.data(withJSONObject: object), configuration: config())
        XCTAssertEqual(result.candidates.count, 1)
    }
    func testCommentaryIsNeverParsedAsFinalStructuredAnswer() throws {
        var object = try JSONSerialization.jsonObject(with: response(value: "Drake", id: UUID())) as! [String: Any]
        var final = (object["output"] as! [[String: Any]])[0]
        final["phase"] = "final_answer"
        object["output"] = [
            ["phase": "commentary", "content": [["type": "output_text", "text": "Intermediate text {not valid JSON}"]]],
            final
        ]
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Drake","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: JSONSerialization.data(withJSONObject: object), configuration: config())
        XCTAssertEqual(result.candidates.count, 1)
        object["output"] = [["phase": "commentary", "content": [["type": "output_text", "text": "{\"facts\":[]}"]]]]
        XCTAssertThrowsError(try CloudExtractor.decode(decisions: decisions, responses: JSONSerialization.data(withJSONObject: object), configuration: config()))
    }
    func testProvisionalNamedOtherRequiresOptInDirectEvidenceAndEmptyUnlockedField() throws {
        var config = config()
        config.groups[0].fields[0].options?.append("Other")
        config.groups[0].fields[0].allowTentativeNamedOther = true
        let callID = UUID()
        let segment = TranscriptEntry(callID: callID, sequence: 1, speaker: .customer, text: "We use NimbusHost.")
        let fact: [String: Any] = ["field_key": "software", "value": "Other", "other_detail": "NimbusHost", "confidence": 0.96,
                                  "estimated": false, "segment_id": segment.id.uuidString, "quote": segment.text, "retracts_previous": false]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["facts": [fact]]), as: UTF8.self)
        let response = try JSONSerialization.data(withJSONObject: ["output": [["content": [["type": "output_text", "text": payload]]]]])
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Drake","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: response, configuration: config)
        let candidate = try XCTUnwrap(result.candidates.first)
        XCTAssertTrue(candidate.requiresDirectCustomerEvidence)
        XCTAssertEqual(candidate.confidence, config.thresholds(for: config.fields[0]).tentative)
        for mode in ["empty", "filled", "locked", "seller", "debrief"] {
            var company = CompanyScorecard(name: "Synthetic", configuration: config)
            var source = segment
            if mode == "filled" { var old = FactRecord(); old.value = .string("Lacerte"); company.facts["software"] = old }
            if mode == "locked" { var old = FactRecord(); old.locked = true; company.facts["software"] = old }
            if mode == "seller" || mode == "debrief" { source.speaker = .salesperson; source.debrief = mode == "debrief" }
            let job = ExtractionJob(company: company, callID: callID, configuration: config, segments: [source])
            let outcome = FactReducer.apply(candidate, job: job, currentSegments: [source.id: source], configuration: config, company: &company)
            if mode == "empty" || mode == "debrief" { XCTAssertEqual(outcome, .updated) }
            else { if case .rejected = outcome {} else { XCTFail("Provisional Other changed \(mode)") } }
        }
        for invalidChoice in ["\"Unlisted invalid choice\"", "null"] {
            let malformed = Data("{\"answers\":[{\"type\":\"choice\",\"name\":\"software\",\"choice\":\(invalidChoice),\"confidence\":0.99}]}".utf8)
            XCTAssertTrue(try CloudExtractor.decode(decisions: malformed, responses: response, configuration: config).candidates.isEmpty)
        }
        config.groups[0].fields[0].allowTentativeNamedOther = false
        XCTAssertTrue(try CloudExtractor.decode(decisions: decisions, responses: response, configuration: config).candidates.isEmpty)
        config.groups[0].fields[0].allowTentativeNamedOther = true
        config.groups[0].fields[0].aliases = ["Drake": ["NimbusHost"]]
        XCTAssertTrue(try CloudExtractor.decode(decisions: decisions, responses: response, configuration: config).candidates.isEmpty)
    }
    func testAliasNormalizesBeforeClassifierAgreement() throws {
        var config = config(); config.groups[0].fields[0].aliases = ["Drake": ["Drak"]]
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Drake","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: response(value: "Drak", id: UUID()), configuration: config)
        XCTAssertEqual(result.candidates.first?.value, .string("Drake"))
        XCTAssertTrue(result.reviewCandidates.isEmpty)
    }
    func testAcceptedCandidateUsesLowerConfidence() throws {
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Drake","confidence":0.81}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: response(value: "Drake", id: UUID()), configuration: config())
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates[0].confidence, 0.81)
    }
    func testInvalidTypedOptionDoesNotStopEntireTranscriptQueue() throws {
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Invalid option","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: response(value: "Invalid option", id: UUID()), configuration: config())
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
    }
    func testMultipleMentionedOptionsUseDecisionPrimaryWithoutStoppingQueue() throws {
        var responseObject = try JSONSerialization.jsonObject(with: response(value: "Lacerte", id: UUID())) as! [String: Any]
        var outputs = responseObject["output"] as! [[String: Any]]
        var contents = outputs[0]["content"] as! [[String: Any]]
        var payload = try JSONSerialization.jsonObject(with: Data((contents[0]["text"] as! String).utf8)) as! [String: Any]
        var facts = payload["facts"] as! [[String: Any]]
        var second = facts[0]; second["value"] = "Drake"
        facts.append(second); payload["facts"] = facts
        contents[0]["text"] = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        outputs[0]["content"] = contents; responseObject["output"] = outputs
        let decisions = Data(#"{"answers":[{"type":"choice","name":"software","choice":"Drake","confidence":0.99}]}"#.utf8)
        let result = try CloudExtractor.decode(decisions: decisions, responses: JSONSerialization.data(withJSONObject: responseObject), configuration: config())
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates.first?.value, .string("Drake"))
    }
    func testQuotaErrorPreventsRepeatedEndpointCalls() async throws {
        let transport = MockTransport(status: 429, payload: #"{"error":{"code":"credit_balance_exhausted"}}"#)
        let client = try OpenAIClient(key: "fake-test-key", transport: transport)
        for _ in 0..<3 {
            do { _ = try await client.post(endpoint: "responses", body: Data("{}".utf8)); XCTFail("Expected quota failure") }
            catch { XCTAssertEqual(error as? OpenAIError, .quota) }
        }
        let count = await transport.count
        XCTAssertEqual(count, 1)
    }
    func testBudgetPreventsNetworkAndUnknownEndpointCannotReceiveKey() async throws {
        let transport = MockTransport(status: 200, payload: "{}")
        let client = try OpenAIClient(key: "fake-test-key", transport: transport, budgetUSD: 0)
        do { _ = try await client.post(endpoint: "responses", body: Data("{}".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? OpenAIError, .budget) }
        do { _ = try await client.post(endpoint: "https://example.com", body: Data("{}".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? OpenAIError, .invalidResponse) }
        let count = await transport.count
        XCTAssertEqual(count, 0)
    }
    func testBudgetLedgerSurvivesReconstruction() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.json")
        let transport = MockTransport(status: 200, payload: #"{"usage":{"input_tokens":1000,"output_tokens":100}}"#)
        let first = try OpenAIClient(key: "fake-test-key", transport: transport, ledgerURL: url)
        _ = try await first.post(endpoint: "responses", body: Data("{}".utf8))
        let initialUsage = await first.usage()
        let second = try OpenAIClient(key: "fake-test-key", transport: transport, ledgerURL: url)
        let reopenedUsage = await second.usage()
        XCTAssertEqual(initialUsage.chargedOrReservedUSD, reopenedUsage.chargedOrReservedUSD)
        XCTAssertEqual(reopenedUsage.requests.count, 1)
        XCTAssertGreaterThan(reopenedUsage.chargedOrReservedUSD, 0)
    }
}
