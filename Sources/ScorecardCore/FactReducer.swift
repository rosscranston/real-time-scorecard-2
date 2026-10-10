import Foundation

public enum ApplyResult: Equatable, Sendable {
    case updated, proposed, unchanged, rejected(String)
}

public enum FactReducer {
    public static func apply(_ candidate: FactCandidate, job: ExtractionJob,
                             currentSegments: [UUID: TranscriptEntry],
                             configuration: ScorecardConfiguration,
                             company: inout CompanyScorecard) -> ApplyResult {
        guard job.companyID == company.id, job.configurationID == company.configurationID,
              configuration.id == company.configurationID,
              job.configurationRevision == configuration.revision,
              company.configurationRevision == configuration.revision else {
            return .rejected("Company or configuration changed.")
        }
        guard let field = configuration.fields.first(where: { $0.key == candidate.fieldKey }),
              field.isAutomatic else { return .rejected("Field is not tracked automatically.") }
        let before = company.facts[field.key] ?? FactRecord()
        guard job.fieldVersions[field.key] == before.version else { return .rejected("Field changed after request.") }
        guard let sent = job.segments.first(where: { $0.id == candidate.segmentID }),
              let segment = currentSegments[candidate.segmentID],
              segment.callID == job.callID, sent.callID == job.callID,
              segment.revision == sent.revision, segment.text == sent.text,
              segment.isFinal, segment.sequence > before.clearedThroughSequence,
              segment.sequence >= before.lastEvidenceSequence else { return .rejected("Evidence is stale or missing.") }
        let quote = candidate.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty, segment.text.contains(quote) else { return .rejected("Quote does not match transcript.") }
        let policy = field.sourcePolicy ?? "either"
        guard policy == "either" || policy == segment.speaker.rawValue || segment.debrief else {
            return .rejected("Speaker is not permitted for this field.")
        }
        guard candidate.confidence.isFinite, (0...1).contains(candidate.confidence) else {
            return .rejected("Invalid confidence.")
        }
        let value: JSONValue
        do { value = try field.validated(candidate.value, otherDetail: candidate.otherDetail) }
        catch { return .rejected(error.localizedDescription) }
        if value == .null && !candidate.retractsPrevious { return .unchanged }
        let thresholds = configuration.thresholds(for: field)
        guard candidate.confidence >= thresholds.tentative else { return .rejected("Insufficient evidence.") }
        let evidence = Evidence(segment: segment, quote: quote)
        let proposed = FactProposal(value: value, otherDetail: candidate.otherDetail,
                                    confidence: candidate.confidence, estimated: candidate.estimated, evidence: [evidence])
        let same = before.value == value && before.otherDetail == candidate.otherDetail
        if same {
            guard !before.locked, candidate.confidence > before.confidence || before.derivedFrom != nil else { return .unchanged }
            var fact = before
            fact.confidence = candidate.confidence; fact.estimated = candidate.estimated
            fact.evidence = [evidence]; fact.version += 1; fact.updatedAt = Date()
            fact.derivedFrom = nil
            company.facts[field.key] = fact
            markChanged(field.key, configuration: configuration, company: &company)
            return .updated
        }
        if before.locked {
            guard candidate.confidence >= thresholds.replacement else { return .rejected("Conflict is too weak.") }
            if let pending = before.proposal,
               (pending.evidence.map(\.sequence).max() ?? -1) > segment.sequence { return .rejected("A newer conflict is already proposed.") }
            if before.dismissedProposalFingerprint == proposed.fingerprint || before.proposal == proposed { return .unchanged }
            var fact = before; fact.proposal = proposed
            // Proposals do not alter the locked value or its version/updated time.
            company.facts[field.key] = fact
            return .proposed
        }
        if before.value != .null {
            guard candidate.confidence >= thresholds.replacement else { return .rejected("Replacement needs stronger evidence.") }
            guard !before.evidence.contains(evidence) else { return .unchanged }
        }
        var fact = before
        fact.value = value; fact.otherDetail = candidate.otherDetail
        fact.confidence = candidate.confidence; fact.estimated = candidate.estimated
        fact.evidence = [evidence]; fact.proposal = nil; fact.version += 1; fact.updatedAt = Date()
        fact.dismissedProposalFingerprint = nil
        fact.derivedFrom = nil
        company.facts[field.key] = fact
        company.latestSequence = max(company.latestSequence, segment.sequence)
        markChanged(field.key, configuration: configuration, company: &company)
        return .updated
    }

    @discardableResult
    public static func manualEdit(field: FieldDefinition, text: String, configuration: ScorecardConfiguration,
                                  company: inout CompanyScorecard) throws -> ChangeEvent {
        let (value, detail) = try field.parseManual(text)
        let before = company.facts[field.key] ?? FactRecord()
        remember(field.key, before: before, company: &company)
        var after = before
        after.value = value; after.otherDetail = detail; after.locked = true
        after.confidence = 1; after.estimated = false; after.version += 1
        after.updatedAt = Date(); after.proposal = nil; after.dismissedProposalFingerprint = nil
        after.derivedFrom = nil
        after.evidence = [Evidence(quote: value == .null ? "Manually cleared" : "Manually entered: \(text)", source: .manual)]
        if value == .null { after.clearedThroughSequence = company.latestSequence }
        company.facts[field.key] = after
        markChanged(field.key, configuration: configuration, company: &company)
        return ChangeEvent(company: company, fieldKey: field.key, action: "manual_edit", before: before, after: after)
    }

    @discardableResult
    public static func clear(fieldKey: String, configuration: ScorecardConfiguration, company: inout CompanyScorecard) -> ChangeEvent {
        let before = company.facts[fieldKey] ?? FactRecord()
        remember(fieldKey, before: before, company: &company)
        var after = before
        after.value = .null; after.otherDetail = nil; after.confidence = 0
        after.derivedFrom = nil
        after.proposal = nil; after.evidence = []; after.estimated = false
        after.clearedThroughSequence = company.latestSequence; after.version += 1; after.updatedAt = Date()
        // Preserve explicit lock state; unlocked clearing waits for new evidence.
        company.facts[fieldKey] = after
        markChanged(fieldKey, configuration: configuration, company: &company)
        return ChangeEvent(company: company, fieldKey: fieldKey, action: "clear", before: before, after: after)
    }

    @discardableResult
    public static func toggleLock(fieldKey: String, company: inout CompanyScorecard) -> ChangeEvent {
        let before = company.facts[fieldKey] ?? FactRecord()
        remember(fieldKey, before: before, company: &company)
        var after = before; after.locked.toggle(); after.version += 1
        if !after.locked { after.proposal = nil }
        company.facts[fieldKey] = after
        return ChangeEvent(company: company, fieldKey: fieldKey, action: "toggle_lock", before: before, after: after)
    }

    @discardableResult
    public static func acceptProposal(fieldKey: String, configuration: ScorecardConfiguration,
                                      company: inout CompanyScorecard) throws -> ChangeEvent? {
        guard let before = company.facts[fieldKey], let proposal = before.proposal,
              let field = configuration.fields.first(where: { $0.key == fieldKey }) else { return nil }
        let value = try field.validated(proposal.value, otherDetail: proposal.otherDetail)
        remember(fieldKey, before: before, company: &company)
        var after = before
        after.value = value; after.otherDetail = proposal.otherDetail
        after.confidence = proposal.confidence; after.estimated = proposal.estimated
        after.evidence = proposal.evidence; after.locked = true; after.proposal = nil
        after.dismissedProposalFingerprint = nil; after.version += 1; after.updatedAt = Date()
        company.facts[fieldKey] = after
        markChanged(fieldKey, configuration: configuration, company: &company)
        return ChangeEvent(company: company, fieldKey: fieldKey, action: "accept_proposal", before: before, after: after)
    }

    public static func dismissProposal(fieldKey: String, company: inout CompanyScorecard) {
        guard var fact = company.facts[fieldKey], let proposal = fact.proposal else { return }
        fact.dismissedProposalFingerprint = proposal.fingerprint; fact.proposal = nil
        company.facts[fieldKey] = fact
    }

    @discardableResult
    public static func undo(configuration: ScorecardConfiguration, company: inout CompanyScorecard) -> ChangeEvent? {
        guard let undo = company.undoStack.popLast() else { return nil }
        let before = company.facts[undo.fieldKey] ?? FactRecord()
        var after = undo.previous
        after.version = before.version + 1 // Old API snapshots never become valid again.
        after.updatedAt = Date()
        company.facts[undo.fieldKey] = after
        markChanged(undo.fieldKey, configuration: configuration, company: &company)
        return ChangeEvent(company: company, fieldKey: undo.fieldKey, action: "undo", before: before, after: after)
    }
    public static func setCollapsed(_ collapsed: Bool, sectionID: String, company: inout CompanyScorecard) {
        if collapsed { company.collapsedSections.insert(sectionID) }
        else { company.collapsedSections.remove(sectionID); company.unreadFields[sectionID] = [] }
    }
    public static func displayedFact(_ fact: FactRecord?, field: FieldDefinition) -> FactRecord? {
        guard let fact, fact.value != .null, (try? field.validated(fact.value, otherDetail: fact.otherDetail)) != nil else { return nil }
        return fact
    }
    private static func remember(_ key: String, before: FactRecord, company: inout CompanyScorecard) {
        company.undoStack.append(UndoEntry(fieldKey: key, previous: before))
        if company.undoStack.count > 100 { company.undoStack.removeFirst(company.undoStack.count - 100) }
    }
    static func markChanged(_ key: String, configuration: ScorecardConfiguration, company: inout CompanyScorecard) {
        guard let group = configuration.groups.first(where: { $0.fields.contains(where: { $0.key == key }) }),
              company.collapsedSections.contains(group.id) else { return }
        company.unreadFields[group.id, default: []].insert(key)
    }
}
