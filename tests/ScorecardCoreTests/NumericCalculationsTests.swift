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
        XCTAssertEqual(company.facts["business"]?.value, .null)
        XCTAssertNotNil(company.facts["business"]?.calculationConflict)
        set("business", 50, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["total"]?.value, .number(100))
        XCTAssertEqual(company.facts["personal"]?.value, .number(200))
        XCTAssertNotNil(company.facts["total"]?.calculationConflict)
        set("total", 250, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertTrue(company.facts.values.allSatisfy { $0.calculationConflict == nil })
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
    func testPercentageRoundingTolerancePreservesDirectAndLockedAnswers() throws {
        var config = config()
        var percent = FieldDefinition(key: "mix", label: "Individual percent", type: "number")
        percent.min = 0; percent.max = 100; percent.integer = false
        config.groups[0].fields.append(percent)
        config.calculations?.append(NumericCalculation(id: "mix", target: "mix", inputs: ["personal", "business"],
            operation: .percentOfSum, decimalPlaces: 2, comparisonTolerance: 0.05))
        var company = CompanyScorecard(name: "Test", configuration: config)
        set("personal", 528, company: &company); set("business", 156, company: &company)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["mix"]?.value, .number(77.19))
        XCTAssertNotNil(company.facts["mix"]?.derivedFrom)
        XCTAssertEqual(company.facts["mix"]?.evidence.first?.source, .calculated)

        // The customer may give a one-decimal percentage; the app should not
        // replace it or report a contradiction over hundredths of a point.
        var direct = FactRecord(); direct.value = .number(77.2); direct.confidence = 0.99
        direct.evidence = [Evidence(quote: "77.2 percent are personal", source: .call, sequence: 3)]
        company.facts["mix"] = direct
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["mix"]?.value, .number(77.2))
        XCTAssertNil(company.facts["mix"]?.calculationConflict)
        company.facts["mix"]?.locked = true
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertNil(company.facts["mix"]?.proposal)
        XCTAssertTrue(company.facts["mix"]?.locked == true)

        company.facts["mix"]?.value = .number(70)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertEqual(company.facts["mix"]?.value, .number(70))
        XCTAssertEqual(company.facts["mix"]?.proposal?.value, .number(77.19))
        XCTAssertNotNil(company.facts["mix"]?.calculationConflict)

        // A later correction close enough to the calculation removes only the
        // calculated proposal/conflict, never the lock or stated value.
        company.facts["mix"]?.value = .number(77.2)
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertNil(company.facts["mix"]?.proposal)
        XCTAssertNil(company.facts["mix"]?.calculationConflict)
        XCTAssertTrue(company.facts["mix"]?.locked == true)

        config.calculations?[3].comparisonTolerance = nil
        _ = NumericDeriver.recalculate(configuration: config, company: &company)
        XCTAssertNotNil(company.facts["mix"]?.calculationConflict) // Other configurations remain strict.
    }

    func testComparisonToleranceSurvivesJSONAndRejectsInvalidValues() throws {
        var config = config()
        config.calculations?[0].comparisonTolerance = 0.05
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoded = try ScorecardConfiguration.load(encoder.encode(config))
        XCTAssertEqual(decoded.calculations?[0].comparisonTolerance, 0.05)
        for invalid in [-0.01, Double.infinity, Double.nan] {
            config.calculations?[0].comparisonTolerance = invalid
            XCTAssertThrowsError(try config.validate())
        }
    }
}
