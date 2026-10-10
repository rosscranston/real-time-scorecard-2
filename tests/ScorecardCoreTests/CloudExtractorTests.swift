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

final class CloudExtractorTests: XCTestCase {
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
