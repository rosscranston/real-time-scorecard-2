import Foundation

public enum ConfigurationError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        if case .invalid(let message) = self { return message }; return nil
    }
}

public struct ConfidenceThresholds: Codable, Equatable, Sendable {
    public var tentative: Double = 0.55
    public var initial: Double = 0.75
    public var replacement: Double = 0.90
    public var calibrated: Bool = false
    public init() {}
}

public struct FieldDefinition: Codable, Identifiable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var type: String
    public var options: [String]?
    public var aliases: [String: [String]]?
    public var min: Double?
    public var max: Double?
    public var integer: Bool?
    public var visible: Bool?
    public var automaticExtraction: Bool?
    public var extractionRoute: String?
    public var sourcePolicy: String?
    public var multiple: Bool?
    public var allowOther: Bool?
    public var allowTentativeNamedOther: Bool?
    public var requiresEvidenceGate: Bool?
    public var evidenceRule: String?
    public var confidence: ConfidenceThresholds?
    public var sourceMetadata: [String: JSONValue]?
    public var role: String?
    public var selectionPolicy: String?
    public var retainSecondaryEvidence: Bool?
    public var unknownValue: JSONValue?
    public var currency: String?
    public var decisionValues: [JSONValue]?
    public var decisionUnknownMapping: [String: JSONValue]?
    public var addedBy: String?
    public var id: String { key }
    public var isVisible: Bool { visible ?? true }
    public var isAutomatic: Bool { automaticExtraction ?? true }
    public var isNumeric: Bool { type == "number" || type == "currency_usd" }
    public init(key: String, label: String, type: String, options: [String]? = nil) {
        self.key = key; self.label = label; self.type = type; self.options = options
    }

    public func validated(_ value: JSONValue, otherDetail: String? = nil) throws -> JSONValue {
        if value == .null { return value }
        switch (type, value) {
        case ("select", .string(let text)):
            let canonical = options?.first(where: { $0.caseInsensitiveCompare(text) == .orderedSame })
                ?? aliases?.first(where: { $0.value.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) })?.key
            guard let canonical, options?.contains(canonical) == true else {
                throw ConfigurationError.invalid("Value is not an allowed option for \(label).")
            }
            if canonical == "Other", (otherDetail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                throw ConfigurationError.invalid("Other needs a specific value.")
            }
            return .string(canonical)
        case ("number", .number(let n)), ("currency_usd", .number(let n)):
            guard n.isFinite, min.map({ n >= $0 }) ?? true, max.map({ n <= $0 }) ?? true,
                  !(integer ?? (type == "number")) || n.rounded() == n else {
                throw ConfigurationError.invalid("Invalid number for \(label).")
            }
        case ("boolean", .bool): break
        case ("string", .string(let text)), ("email", .string(let text)),
             ("phone", .string(let text)), ("url", .string(let text)), ("date", .string(let text)):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigurationError.invalid("Use clear for an empty value.")
            }
            if type == "email", !text.contains("@") { throw ConfigurationError.invalid("Enter an email address.") }
            if type == "url", !["https", "http"].contains(URL(string: text)?.scheme?.lowercased() ?? "") {
                throw ConfigurationError.invalid("Enter an HTTP or HTTPS URL.")
            }
            if type == "date" {
                let format = DateFormatter()
                format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0)
                format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
                guard let date = format.date(from: text), format.string(from: date) == text else {
                    throw ConfigurationError.invalid("Use a valid YYYY-MM-DD date.")
                }
            }
        default: throw ConfigurationError.invalid("Value type does not match \(label).")
        }
        return value
    }

    public func parseManual(_ text: String) throws -> (JSONValue, String?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return (.null, nil) }
        var value: JSONValue = .string(text)
        var detail: String?
        if isNumeric {
            guard let n = Double(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) else {
                throw ConfigurationError.invalid("Enter one number.")
            }
            value = .number(n)
        } else if type == "boolean" {
            if ["yes", "true", "1"].contains(text.lowercased()) { value = .bool(true) }
            else if ["no", "false", "0"].contains(text.lowercased()) { value = .bool(false) }
            else { throw ConfigurationError.invalid("Enter Yes or No.") }
        } else if type == "select", text.lowercased().hasPrefix("other:") {
            value = .string("Other"); detail = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        return (try validated(value, otherDetail: detail), detail)
    }
}

public struct FieldGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var fields: [FieldDefinition]
    public init(id: String, label: String, fields: [FieldDefinition]) {
        self.id = id; self.label = label; self.fields = fields
    }
}
public struct CallLayout: Codable, Equatable, Sendable {
    public var groupOrder: [String]
    public var priorityFields: [String]
    public init(groupOrder: [String], priorityFields: [String] = []) {
        self.groupOrder = groupOrder; self.priorityFields = priorityFields
    }
}
public struct ScorecardConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var revision: Int
    public var title: String
    public var maxFields: Int
    public var groups: [FieldGroup]
    public var layouts: [String: CallLayout]
    public var defaults: [String: JSONValue]?
    public var status: String?
    public var sourceCatalog: [String: JSONValue]?
    public var integrations: [String: JSONValue]?
    public var draftNotes: [String]?
    public var calculations: [NumericCalculation]?
    public var fields: [FieldDefinition] { groups.flatMap(\.fields) }
    public init(id: String, title: String, groups: [FieldGroup]) {
        self.schemaVersion = 1; self.id = id; self.title = title; self.groups = groups
        self.revision = 1; self.maxFields = 50
        self.layouts = ["initial": CallLayout(groupOrder: groups.map(\.id))]
    }
    public static func load(_ data: Data) throws -> Self {
        let config = try ScorecardCoding.decoder().decode(Self.self, from: data)
        try config.validate()
        return config
    }
    public func validate() throws {
        guard schemaVersion == 1, revision > 0, !id.isEmpty, !title.isEmpty else {
            throw ConfigurationError.invalid("Unsupported configuration version or missing identity.")
        }
        guard maxFields > 0, maxFields <= 50, !fields.isEmpty, fields.count <= maxFields else {
            throw ConfigurationError.invalid("A configuration must contain 1–50 fields.")
        }
        let keys = fields.map(\.key)
        guard Set(keys).count == keys.count, Set(groups.map(\.id)).count == groups.count else {
            throw ConfigurationError.invalid("Field and section IDs must be unique.")
        }
        let supported = Set(["string", "number", "currency_usd", "boolean", "date", "email", "phone", "url", "select"])
        for f in fields {
            guard f.key.range(of: "^[a-zA-Z][a-zA-Z0-9_]*$", options: .regularExpression) != nil,
                  !f.label.isEmpty, supported.contains(f.type), f.multiple != true else {
                throw ConfigurationError.invalid("Invalid field \(f.key). Version 1 uses one value per field.")
            }
            if f.type == "select" {
                guard let options = f.options, !options.isEmpty, Set(options).count == options.count,
                      options.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                    throw ConfigurationError.invalid("Select field \(f.label) needs distinct options.")
                }
                for target in f.aliases?.keys ?? Dictionary<String, [String]>().keys {
                    guard options.contains(target) else { throw ConfigurationError.invalid("Alias target is not an option.") }
                }
            }
            if let min = f.min, let max = f.max, min > max { throw ConfigurationError.invalid("Invalid numeric bounds.") }
            if f.requiresEvidenceGate == true && !f.isNumeric {
                throw ConfigurationError.invalid("Evidence gates currently apply to numeric fields only.")
            }
            guard ["either", "salesperson", "customer"].contains(f.sourcePolicy ?? "either") else {
                throw ConfigurationError.invalid("Unknown speaker policy.")
            }
            let t = thresholds(for: f)
            guard t.tentative.isFinite, t.initial.isFinite, t.replacement.isFinite,
                  0 <= t.tentative, t.tentative <= t.initial, t.initial <= t.replacement, t.replacement <= 1 else {
                throw ConfigurationError.invalid("Confidence thresholds must increase from 0 to 1.")
            }
        }
        for layout in layouts.values {
            guard Set(layout.groupOrder) == Set(groups.map(\.id)), layout.groupOrder.count == groups.count,
                  Set(layout.priorityFields).isSubset(of: Set(keys)),
                  Set(layout.priorityFields).count == layout.priorityFields.count else {
                throw ConfigurationError.invalid("Layout references invalid or duplicated sections/fields.")
            }
        }
        let formulas = calculations ?? []
        guard Set(formulas.map(\.id)).count == formulas.count else { throw ConfigurationError.invalid("Calculation IDs must be unique.") }
        for formula in formulas {
            guard !formula.id.isEmpty, formula.inputs.count == 2, Set(formula.inputs).count == 2,
                  !formula.inputs.contains(formula.target),
                  fields.first(where: { $0.key == formula.target })?.isNumeric == true,
                  formula.inputs.allSatisfy({ key in fields.first(where: { $0.key == key })?.isNumeric == true }),
                  (0...6).contains(formula.decimalPlaces ?? 0),
                  (formula.comparisonTolerance ?? 0).isFinite, (formula.comparisonTolerance ?? 0) >= 0 else {
                throw ConfigurationError.invalid("Calculation references invalid numeric fields or precision.")
            }
        }
    }
    public func thresholds(for field: FieldDefinition) -> ConfidenceThresholds {
        if let custom = field.confidence { return custom }
        guard case .object(let values) = defaults?["confidence"] else { return ConfidenceThresholds() }
        var t = ConfidenceThresholds()
        t.tentative = values["tentative"]?.number ?? t.tentative
        t.initial = values["initial"]?.number ?? t.initial
        t.replacement = values["replacement"]?.number ?? t.replacement
        return t
    }
    public func orderedGroups(for callType: String) -> [FieldGroup] {
        guard let layout = layouts[callType] else { return groups }
        return layout.groupOrder.compactMap { id in
            guard var group = groups.first(where: { $0.id == id }) else { return nil }
            let ranks = Dictionary(uniqueKeysWithValues: layout.priorityFields.enumerated().map { ($1, $0) })
            group.fields = group.fields.enumerated().sorted { a, b in
                let ra = ranks[a.element.key] ?? Int.max, rb = ranks[b.element.key] ?? Int.max
                return ra == rb ? a.offset < b.offset : ra < rb
            }.map(\.element)
            return group
        }
    }
}
