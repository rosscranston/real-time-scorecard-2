import XCTest
@testable import ScorecardCore

final class NumericCalculationsTests: XCTestCase {
    func config() -> ScorecardConfiguration {
        let fields = ["total", "personal", "business"].map { key -> FieldDefinition in
            var field = FieldDefinition(key: key, label: key, type: "number"); field.min = 0; field.integer = true
            return field
        }
        var config = ScorecardConfiguration(id: "math", title: "Math", groups: [FieldGroup(id: "returns", label: "Returns", fields: fields)])
        config.calculations = [
            NumericCalculation(id: "total", target: "total", inputs: ["personal", "business"], operation: .sum),
            NumericCalculation(id: "business", target: "business", inputs: ["total", "personal"], operation: .difference),
            NumericCalculation(id: "personal", target: "personal", inputs: ["total", "business"], operation: .difference)
        ]
        return config
    }
    func set(_ key: String, _ value: Int, company: inout CompanyScorecard) {
        var fact = FactRecord(); fact.value = .number(Double(value)); fact.confidence = 0.99
        fact.version = (company.facts[key]?.version ?? 0) + 1
        fact.evidence = [Evidence(quote: "Customer stated \(value)", source: .call, sequence: fact.version)]
        company.facts[key] = fact
    }
    func testOnlyTwoKnownCountsCanDeriveTheThirdAndChangesRecalculate() {
        let config = config(); var company = CompanyScorecard(name: "Test", configuration: config)
        set("total", 684, company: &company)
        XCTAssertTrue(NumericDeriver.recalculate(configuration: config, company: &company).isEmpty)
        XCTAssertNil(company.facts["business"])
        set("personal", 528, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["business"]?.value, .number(156))
        XCTAssertEqual(company.facts["business"]?.evidence.first?.source, .calculated)
        set("total", 700, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["business"]?.value, .number(172))
        company.facts.removeValue(forKey: "personal")
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["business"]?.value, .null)
        XCTAssertNil(company.facts["personal"]) // No circular reconstruction.
    }
    func testCalculatedValuesNeverOverwriteLockedFacts() {
        let config = config(); var company = CompanyScorecard(name: "Test", configuration: config)
        set("total", 684, company: &company); set("personal", 528, company: &company)
        set("business", 100, company: &company); company.facts["business"]?.locked = true
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["business"]?.value, .number(100))
        XCTAssertEqual(company.facts["business"]?.proposal?.value, .number(156))
        XCTAssertTrue(company.facts["business"]?.locked == true)
    }
    func testDirectAnswerAndInvalidNegativeRemainderArePreserved() {
        let config = config(); var company = CompanyScorecard(name: "Test", configuration: config)
        set("total", 100, company: &company); set("personal", 200, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertNil(company.facts["business"])
        set("business", 50, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["total"]?.value, .number(100))
        XCTAssertEqual(company.facts["personal"]?.value, .number(200))
    }
    func testManualClearWaitsForNewInputAndInvalidFormulaFailsImport() throws {
        var config = config(); var company = CompanyScorecard(name: "Test", configuration: config)
        set("total", 684, company: &company); set("personal", 528, company: &company)
        company.latestSequence = 3
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        _ = FactReducer.clear(fieldKey: "business", configuration: config, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["business"]?.value, .null)
        set("personal", 500, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["business"]?.value, .number(184))
        config.calculations?[0].inputs = ["missing", "business"]
        XCTAssertThrowsError(try config.validate())
    }
}
