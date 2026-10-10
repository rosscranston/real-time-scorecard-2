import Foundation

public struct NumericCalculation: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case sum, difference, percent, percentOfSum = "percent_of_sum", complementPercent = "complement_percent"
    }
    public var id: String
    public var target: String
    public var inputs: [String]
    public var operation: Operation
    public var decimalPlaces: Int?
    /// Absolute units tolerated when comparing direct/locked evidence with this
    /// formula. Does not change the displayed value or calculation precision.
    public var comparisonTolerance: Double?
    public init(id: String, target: String, inputs: [String], operation: Operation, decimalPlaces: Int? = nil,
                comparisonTolerance: Double? = nil) {
        self.id = id; self.target = target; self.inputs = inputs; self.operation = operation; self.decimalPlaces = decimalPlaces
        self.comparisonTolerance = comparisonTolerance
    }
    func agrees(_ actual: Double, with calculated: Double) -> Bool {
        abs(actual - calculated) <= (comparisonTolerance ?? 0.000001) + 0.000000001
    }
    func evaluate(_ a: Double, _ b: Double) -> Double? {
        let raw: Double
        switch operation {
        case .sum: raw = a + b
        case .difference: raw = a - b
        case .percent: guard b != 0 else { return nil }; raw = a / b * 100
        case .percentOfSum: guard a + b != 0 else { return nil }; raw = a / (a + b) * 100
        case .complementPercent: guard b != 0 else { return nil }; raw = (b - a) / b * 100
        }
        guard raw.isFinite else { return nil }
        let factor = pow(10, Double(decimalPlaces ?? 0))
        return (raw * factor).rounded(.toNearestOrAwayFromZero) / factor
    }
}

public enum NumericDeriver {
    /// Only directly supported or explicitly locked inputs participate. This
    /// prevents inverse formulas from creating circular, self-supporting facts.
    public static func recalculate(configuration: ScorecardConfiguration, company: inout CompanyScorecard) -> [ChangeEvent] {
        let formulas = configuration.calculations ?? []
        let base = company.facts.filter { _, fact in fact.value.number != nil && (fact.derivedFrom == nil || fact.locked) }
        var handled = Set<String>()
        var events: [ChangeEvent] = []
        for formula in formulas {
            guard !handled.contains(formula.target),
                  let field = configuration.fields.first(where: { $0.key == formula.target }),
                  let left = base[formula.inputs[0]], let right = base[formula.inputs[1]],
                  let a = left.value.number, let b = right.value.number,
                  let numeric = formula.evaluate(a, b),
                  let value = try? field.validated(.number(numeric)) else { continue }
            let before = company.facts[formula.target] ?? FactRecord()
            let confidence = min(left.confidence, right.confidence)
            guard confidence >= configuration.thresholds(for: field).tentative else { continue }
            let sequence = max(left.lastEvidenceSequence, right.lastEvidenceSequence)
            guard before.clearedThroughSequence < 0 || sequence > before.clearedThroughSequence ||
                    max(left.updatedAt, right.updatedAt) > before.updatedAt else { continue }
            handled.insert(formula.target)
            let description = "\(formula.operation.rawValue): \(formula.inputs[0]) = \(left.display), \(formula.inputs[1]) = \(right.display)"
            let evidence = [Evidence(quote: description, source: .calculated, sequence: sequence)] + left.evidence + right.evidence
            let dependencies = [formula.inputs[0]: left.version, formula.inputs[1]: right.version]
            let estimated = left.estimated || right.estimated
            var after = before
            if before.locked {
                let agrees = before.value.number.map { formula.agrees($0, with: numeric) } ?? false
                if !agrees, confidence >= configuration.thresholds(for: field).replacement {
                    let proposal = FactProposal(value: value, confidence: confidence, estimated: estimated, evidence: evidence)
                    if before.dismissedProposalFingerprint != proposal.fingerprint { after.proposal = proposal }
                } else if before.proposal?.evidence.first?.source == .calculated { after.proposal = nil }
            } else if before.value == .null || before.derivedFrom != nil {
                after.value = value; after.confidence = confidence; after.estimated = estimated
                after.evidence = evidence; after.derivedFrom = dependencies; after.proposal = nil
                if before.value != value || before.derivedFrom != dependencies || before.confidence != confidence {
                    after.version += 1; after.updatedAt = Date()
                }
            }
            if after != before {
                company.facts[field.key] = after
                if after.value != before.value { FactReducer.markChanged(field.key, configuration: configuration, company: &company) }
                events.append(ChangeEvent(company: company, fieldKey: field.key, action: before.locked ? "calculated_proposal" : "calculated",
                                          before: before, after: after))
            }
        }
        // An unlocked calculation with missing inputs must not retain a stale
        // number after an input is cleared or a formula disappears.
        for (key, before) in company.facts where before.derivedFrom != nil && !before.locked && !handled.contains(key) {
            guard configuration.fields.contains(where: { $0.key == key }), before.value != .null else { continue }
            var after = before
            after.value = .null; after.evidence = []; after.confidence = 0; after.proposal = nil
            after.version += 1; after.updatedAt = Date(); after.derivedFrom = nil
            company.facts[key] = after
            FactReducer.markChanged(key, configuration: configuration, company: &company)
            events.append(ChangeEvent(company: company, fieldKey: key, action: "calculation_inputs_missing", before: before, after: after))
        }
        // Report contradictory direct evidence without choosing which spoken
        // input was wrong. Invalid results never become displayed numbers.
        var conflicts: [String: String] = [:]
        for formula in formulas {
            guard let field = configuration.fields.first(where: { $0.key == formula.target }),
                  let left = base[formula.inputs[0]], let right = base[formula.inputs[1]],
                  let a = left.value.number, let b = right.value.number,
                  min(left.confidence, right.confidence) >= configuration.thresholds(for: field).tentative,
                  let result = formula.evaluate(a, b) else { continue }
            let invalid = (try? field.validated(.number(result))) == nil
            let disagrees = base[formula.target]?.value.number.map { !formula.agrees($0, with: result) } ?? false
            if invalid || disagrees {
                conflicts[formula.target] = "Values disagree: \(formula.operation.rawValue) of \(formula.inputs[0]) (\(left.display)) and \(formula.inputs[1]) (\(right.display)) gives \(JSONValue.number(result).display). Check the source values."
            }
        }
        for key in Set(company.facts.keys).union(conflicts.keys) {
            let before = company.facts[key] ?? FactRecord()
            guard before.calculationConflict != conflicts[key] else { continue }
            var after = before; after.calculationConflict = conflicts[key]
            company.facts[key] = after
            events.append(ChangeEvent(company: company, fieldKey: key, action: "calculation_conflict", before: before, after: after))
        }
        return events
    }
}
