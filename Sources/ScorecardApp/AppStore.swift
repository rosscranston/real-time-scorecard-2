import SwiftUI
import Combine
import ScorecardCore
import EventKit
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    @Published var configuration: ScorecardConfiguration?
    @Published var configurations: [ScorecardConfiguration] = []
    @Published var companies: [CompanyScorecard] = []
    @Published var history: [CallRecord] = []
    @Published var pendingCalls: [UUID: Int] = [:]
    @Published var selectedCompany: CompanyScorecard?
    @Published var session: ExtractionSession?
    @Published var eventName = ""
    @Published var firmName = ""
    @Published var callType = "initial"
    @Published var message: String?
    @Published var credentialBusy = false
    @Published var starting = false
    private var sessionKey: String?
    @Published var connectionStatus = "Add a key or test the saved connection"
    @Published var calendarStatus = "Optional · not connected"
    @Published var showTranscript = false
    @Published var showHistory = false
    @Published var showInScreenSharing = false
    @Published var opacity = 1.0
    @Published var lockShortcut = "commandShiftL"
    @Published var transcriptRetentionDays = 30
    @Published var apiBudgetUSD = 5.0
    @Published var usageSummary = "Usage has not been loaded"
    @Published var scorecardViewID = UUID()
    private var renderedVersions: [String: Int] = [:]
    private var renderLatencies: [Double] = []
    @Published var replaying = false
    @Published var transcriptionProvider = "openai"
    @Published var browserBundleID = "com.google.Chrome"
    @Published var audioStatus = "Audio stopped"
    @Published var audioRunning = false
    @Published var audioBusy = false
    private var audioCapture: LiveAudioCapture?
    private var audioTask: Task<Void, Never>?
    private var audioGeneration: UUID?
    private var audioStopping = false
    private var database: ScorecardDatabase?
    private var client: OpenAIClient?
    private var replayTask: Task<Void, Never>?
    private let calendars = EKEventStore()
    var company: CompanyScorecard? { session?.company ?? selectedCompany }
    var active: Bool { session?.call.endedAt == nil && session != nil }
    var busy: Bool { session?.isProcessing == true }

    init() {
        do {
            let db = try ScorecardDatabase(); database = db
            guard let url = Bundle.module.url(forResource: "default-configuration", withExtension: "json") else {
                throw DatabaseError(message: "The app's default configuration is missing.")
            }
            var initial = try ScorecardConfiguration.load(Data(contentsOf: url))
            let saved = try db.configurations()
            if let existing = saved.first(where: { $0.id == initial.id && $0.revision == initial.revision }),
               existing != initial {
                // A user may have created this revision number in Settings. Preserve
                // that configuration when the bundled catalog receives an update.
                initial.revision = (saved.filter { $0.id == initial.id }.map(\.revision).max() ?? initial.revision) + 1
            }
            try db.saveConfiguration(initial)
            configurations = try db.configurations()
            let selected = try db.preference(String.self, key: "activeConfiguration")
            configuration = configurations.first { "\($0.id):\($0.revision)" == selected } ?? initial
            companies = try db.companies(); history = try db.calls()
            pendingCalls = Dictionary(grouping: try db.pendingJobs(), by: \.callID).mapValues(\.count)
            showInScreenSharing = try db.preference(Bool.self, key: "showInScreenSharing") ?? false
            opacity = try db.preference(Double.self, key: "opacity") ?? 1
            lockShortcut = try db.preference(String.self, key: "lockShortcut") ?? "commandShiftL"
            transcriptionProvider = try db.preference(String.self, key: "transcriptionProvider") ?? "openai"
            browserBundleID = try db.preference(String.self, key: "browserBundleID") ?? "com.google.Chrome"
            transcriptRetentionDays = try db.preference(Int.self, key: "transcriptRetentionDays") ?? 30
            apiBudgetUSD = try db.preference(Double.self, key: "apiBudgetUSD") ?? 5
            if transcriptRetentionDays > 0 {
                try db.pruneTranscripts(olderThan: Date().addingTimeInterval(-Double(transcriptRetentionDays) * 86400))
            }
        } catch { message = error.localizedDescription }
    }
    func makeClient(allowKeychainInteraction: Bool = false) async throws -> OpenAIClient {
        if let client { return client }
        let key = try await apiKey(allowInteraction: allowKeychainInteraction)
        if let client { return client }
        let ledger = try ScorecardDatabase.defaultURL().deletingLastPathComponent().appendingPathComponent("api-usage.json")
        let result = try OpenAIClient(key: key, ledgerURL: ledger, budgetUSD: apiBudgetUSD)
        client = result; connectionStatus = "API key available on this Mac"; return result
    }
    private func apiKey(allowInteraction: Bool = false) async throws -> String {
        if let sessionKey { return sessionKey }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        connectionStatus = "Reading saved key · macOS may ask for access"
        // Security.framework can wait for authorization. Never block the main actor.
        do {
            let key = try await Task.detached(priority: .userInitiated) {
                try CredentialStore.load(allowInteraction: allowInteraction) ?? CredentialStore.developerKey(directory: directory)
            }.value
            guard let key else { throw OpenAIError.missingKey }
            sessionKey = key
            return key
        } catch {
            connectionStatus = error.localizedDescription
            throw error
        }
    }

    func importSessionKey() {
        guard !active, !busy, !starting, !credentialBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Use a developer .env key for this session"
        panel.message = "Choose your .env file. Only OPENAI_API_KEY is read; it stays in memory until you quit."
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.allowedContentTypes = []; panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.lastPathComponent == ".env",
              let key = CredentialStore.developerKey(directory: url.deletingLastPathComponent(), environment: [:]),
              !key.contains(where: \.isWhitespace) else {
            connectionStatus = "Choose a .env file containing OPENAI_API_KEY."; return
        }
        sessionKey = key; client = nil; message = nil
        connectionStatus = "Session key loaded · not saved · choose Test text APIs"
    }
    func saveKey(_ key: String) async {
        guard !credentialBusy else { return }
        credentialBusy = true
        connectionStatus = "Saving key · approve the macOS Keychain prompt if shown"
        defer { credentialBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) { try CredentialStore.save(key) }.value
            sessionKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            client = nil; connectionStatus = "Key saved in Keychain"; message = nil
        } catch { connectionStatus = error.localizedDescription; message = error.localizedDescription }
    }
    func removeKey() async {
        guard !credentialBusy else { return }
        credentialBusy = true
        connectionStatus = "Removing saved key…"
        defer { credentialBusy = false }
        do {
            try await Task.detached(priority: .userInitiated) { try CredentialStore.remove() }.value
            sessionKey = nil; client = nil; connectionStatus = "Key removed"
        } catch { connectionStatus = error.localizedDescription; message = error.localizedDescription }
    }
    func testConnection() async {
        do {
            let client = try await makeClient(allowKeychainInteraction: true)
            await client.retryQuotaBlockedEndpoints()
            guard let config = configuration else { return }
            let company = CompanyScorecard(name: "Synthetic connection test", configuration: config)
            let call = CallRecord(company: company, isReplay: true)
            let text = TranscriptEntry(callID: call.id, sequence: 1, speaker: .customer,
                                       text: "We use Drake Desktop on a computer in our office. We prepare 800 returns a year.")
            let result = try await CloudExtractor(client: client).extract(
                job: ExtractionJob(company: company, callID: call.id, configuration: config, segments: [text]),
                company: company, configuration: config)
            connectionStatus = String(format: "Text APIs connected · %.2fs", result.seconds)
        } catch { connectionStatus = error.localizedDescription }
    }
    func start(isReplay: Bool = false) async {
        guard !active, !busy, !audioBusy, !starting, !credentialBusy, let configuration, let database else { return }
        starting = true
        defer { starting = false }
        let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "Name this event before starting."; return }
        do {
            let client = try await makeClient()
            guard self.configuration == configuration else {
                message = "Configuration changed while connecting. Press Start again."; return
            }
            let firm = firmName.trimmingCharacters(in: .whitespacesAndNewlines)
            let companyName = firm.isEmpty ? name : firm
            var company = try database.companies().first {
                $0.name.caseInsensitiveCompare(companyName) == .orderedSame && $0.configurationID == configuration.id
            } ?? CompanyScorecard(name: companyName, configuration: configuration)
            company.configurationRevision = configuration.revision
            var call = CallRecord(company: company, callType: callType, isReplay: isReplay)
            call.eventName = name
            let running = try ExtractionSession(company: company, call: call, configuration: configuration,
                                                database: database, extractor: CloudExtractor(client: client))
            running.onChange = { [weak self] in self?.objectWillChange.send() }
            session = running; selectedCompany = company; message = nil
            scorecardViewID = UUID()
            renderedVersions = [:]; renderLatencies = []
            try refreshHistory()
            if !isReplay { startAudio() }
        } catch { message = error.localizedDescription }
    }
    func stop() {
        replayTask?.cancel(); replayTask = nil; replaying = false
        stopAudio()
        do { try session?.finish(); try refreshHistory() }
        catch { message = error.localizedDescription }
    }
    func saveAudioSettings() {
        do {
            try database?.savePreference(transcriptionProvider, key: "transcriptionProvider")
            try database?.savePreference(browserBundleID, key: "browserBundleID")
        } catch { message = error.localizedDescription }
    }
    func startAudio() {
        guard active, !audioBusy, !audioRunning, let running = session, let configuration else { return }
        guard transcriptionProvider != "transcript" else { audioStatus = "Transcript input"; return }
        audioBusy = true; audioStatus = "Connecting audio…"
        let generation = UUID(); audioGeneration = generation
        let callID = running.call.id
        let origin = Date()
        let sequenceBase = running.company.latestSequence + 1
        let provider = transcriptionProvider
        audioTask = Task { [weak self] in
            guard let self else { return }
            var capture: LiveAudioCapture?
            do {
                let onEvent: OpenAITranscriber.EventHandler = { [weak self] event in
                    Task { @MainActor in
                        guard let self, let current = self.session, current.call.id == callID else { return }
                        let sequence = sequenceBase + Int(max(0, event.startSeconds) * 1000) * 2 + (event.role == .customer ? 1 : 0)
                        var entry = TranscriptEntry(id: event.id, callID: callID, sequence: sequence,
                            speaker: event.role, text: event.text, seconds: origin.timeIntervalSince(current.call.startedAt) + event.startSeconds,
                            sentenceEndedAt: event.sentenceEndedAt)
                        if let previous = current.segments.first(where: { $0.id == event.id }) {
                            if previous.text == event.text { return }
                            entry.revision = previous.revision + 1
                        }
                        do { try current.ingest(entry) } catch { self.message = error.localizedDescription }
                    }
                }
                let onError: OpenAITranscriber.ErrorHandler = { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.session?.call.id == callID, self.audioGeneration == generation else { return }
                        self.message = message; self.audioStatus = "Audio interrupted · reconnect in Settings"
                        self.stopAudio()
                    }
                }
                let mic: any AudioChannel
                let meeting: any AudioChannel
                let onStatus: OpenAITranscriber.ErrorHandler = { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.session?.call.id == callID, self.audioGeneration == generation else { return }
                        self.audioStatus = status
                    }
                }
                if provider == "apple" {
                    mic = AppleSpeechChannel(source: .salesperson, origin: origin, onEvent: onEvent, onError: onError)
                    meeting = AppleSpeechChannel(source: .customer, origin: origin, onEvent: onEvent, onError: onError)
                } else {
                    let key = try await self.apiKey()
                    let billing = try await self.makeClient()
                    let onUsage: OpenAITranscriber.UsageHandler = { seconds in try await billing.recordAudioUpload(seconds: seconds) }
                    let keywords = configuration.fields.flatMap { ($0.options ?? []) + ($0.aliases?.values.flatMap { $0 } ?? []) }
                    mic = CloudSpeechChannel(key: key, role: .salesperson, origin: origin, keywords: keywords,
                                             onEvent: onEvent, onError: onError, onStatus: onStatus, onUsage: onUsage)
                    meeting = CloudSpeechChannel(key: key, role: .customer, origin: origin, keywords: keywords,
                                                 onEvent: onEvent, onError: onError, onStatus: onStatus, onUsage: onUsage)
                }
                let service = LiveAudioCapture(microphone: mic, meeting: meeting, onError: onError)
                capture = service
                try await mic.prepare()
                try Task.checkCancellation()
                try await meeting.prepare()
                try Task.checkCancellation()
                try await service.start(browserBundleID: self.browserBundleID, microphoneID: nil)
                try Task.checkCancellation()
                guard self.active, self.session?.call.id == callID else { throw CancellationError() }
                self.audioCapture = service
                self.audioRunning = true; self.audioStatus = provider == "apple" ? "Apple Speech" : "OpenAI audio"
            } catch {
                await capture?.stop()
                if !(error is CancellationError) {
                    self.audioStatus = "Audio unavailable"
                    self.message = (error as? OpenAIError)?.localizedDescription ?? error.localizedDescription
                }
            }
            if !self.audioStopping { self.audioBusy = false }
        }
    }
    func replayAudioFile(speaker: SpeakerRole) async {
        guard !active, !busy, !audioBusy, !starting, !credentialBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source: AudioFileReplay
        do { source = try AudioFileReplay(url: url) }
        catch { message = "Cannot replay this audio file. Choose a supported recording up to five minutes long."; return }
        eventName = "Audio replay · \(url.deletingPathExtension().lastPathComponent)"
        firmName = "Audio replay \(UUID().uuidString.prefix(8))"
        await start(isReplay: true)
        guard active, let running = session, let configuration else { return }
        let callID = running.call.id
        let sequenceBase = running.company.latestSequence + 1
        let generation = UUID(); audioGeneration = generation
        audioBusy = true; replaying = true; audioStatus = "Connecting audio replay…"
        audioTask = Task { [weak self] in
            guard let self else { return }
            var channel: CloudSpeechChannel?
            var completed = false
            do {
                let key = try await self.apiKey()
                let billing = try await self.makeClient()
                let origin = Date()
                let onEvent: OpenAITranscriber.EventHandler = { [weak self] event in
                    Task { @MainActor in
                        guard let self, let current = self.session, current.call.id == callID else { return }
                        var entry = TranscriptEntry(id: event.id, callID: callID,
                            sequence: sequenceBase + Int(max(0, event.startSeconds) * 1000),
                            speaker: event.role, text: event.text,
                            seconds: origin.timeIntervalSince(current.call.startedAt) + event.startSeconds,
                            sentenceEndedAt: event.sentenceEndedAt)
                        if let previous = current.segments.first(where: { $0.id == event.id }) {
                            if previous.text == event.text { return }
                            entry.revision = previous.revision + 1
                        }
                        do { try current.ingest(entry) } catch { self.message = error.localizedDescription }
                    }
                }
                let onError: OpenAITranscriber.ErrorHandler = { [weak self] detail in
                    Task { @MainActor in
                        guard let self, self.audioGeneration == generation else { return }
                        self.message = detail; self.audioStatus = "Audio replay interrupted"
                        self.stopAudio()
                    }
                }
                let keywords = configuration.fields.flatMap { ($0.options ?? []) + ($0.aliases?.values.flatMap { $0 } ?? []) }
                let service = CloudSpeechChannel(key: key, role: speaker, origin: origin, keywords: keywords,
                    onEvent: onEvent, onError: onError,
                    onUsage: { seconds in try await billing.recordAudioUpload(seconds: seconds) })
                channel = service
                try await service.prepare()
                try Task.checkCancellation()
                self.audioRunning = true; self.audioBusy = false
                self.audioStatus = "Audio file replay · \(speaker.rawValue)"
                try await source.run(channel: service)
                try Task.checkCancellation()
                completed = true
            } catch {
                if !(error is CancellationError) {
                    self.message = (error as? OpenAIError)?.localizedDescription ?? "Audio file replay failed."
                    self.audioStatus = "Audio replay failed"
                }
            }
            // Keep the call and generation available until final transcripts drain.
            self.audioBusy = true
            await channel?.stop()
            await running.waitUntilIdle()
            do { try running.finish(); try self.refreshHistory() }
            catch { self.message = error.localizedDescription }
            self.replaying = false; self.audioRunning = false
            if completed, self.audioGeneration == generation {
                self.audioStatus = "Audio replay complete"; self.audioGeneration = nil
            }
            if !self.audioStopping { self.audioBusy = false }
            await self.refreshUsage()
        }
    }
    func stopAudio() {
        guard !audioStopping, audioCapture != nil || audioBusy || audioRunning else { return }
        audioStopping = true; audioGeneration = nil
        audioTask?.cancel()
        let startup = audioTask
        audioBusy = true
        Task { [weak self] in
            await startup?.value
            guard let self else { return }
            let capture = self.audioCapture; self.audioCapture = nil
            await capture?.stop()
            self.audioRunning = false; self.audioBusy = false
            self.audioStopping = false
            if self.audioStatus == "OpenAI audio" || self.audioStatus == "Apple Speech" { self.audioStatus = "Audio stopped" }
            if self.audioStatus.hasPrefix("Audio file replay") || self.audioStatus == "Connecting audio replay…" {
                self.audioStatus = "Audio replay stopped"
            }
        }
    }
    func retry() async {
        if let client { await client.retryQuotaBlockedEndpoints() }
        session?.resume()
    }
    func ingest(text: String, speaker: SpeakerRole, debrief: Bool) {
        guard let session, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let entry = TranscriptEntry(callID: session.call.id, sequence: session.company.latestSequence + 1,
                                        speaker: speaker, text: text, debrief: debrief, sentenceEndedAt: Date())
            try session.ingest(entry)
        } catch { message = error.localizedDescription }
    }
    func mutate(_ action: (inout CompanyScorecard, ScorecardConfiguration) throws -> [ChangeEvent]) {
        guard let configuration, let database else { return }
        do {
            if let session {
                try session.mutate { company in try action(&company, configuration) }
            } else if var company = selectedCompany {
                var events = try action(&company, configuration)
                events += NumericDeriver.recalculate(configuration: configuration, company: &company)
                try database.saveCompany(company, events: events); selectedCompany = company
            }
        } catch { message = error.localizedDescription }
    }
    func edit(_ field: FieldDefinition, text: String) {
        mutate { company, config in [try FactReducer.manualEdit(field: field, text: text, configuration: config, company: &company)] }
    }
    func toggleLock(_ key: String) {
        mutate { company, _ in [FactReducer.toggleLock(fieldKey: key, company: &company)] }
    }
    func undo() {
        mutate { company, config in FactReducer.undo(configuration: config, company: &company).map { [$0] } ?? [] }
    }
    func undoFromKeyboard() {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            editor.undoManager?.undo()
        } else { undo() }
    }
    func recordVisibleUpdate(_ key: String, version: Int) {
        guard renderedVersions[key] != version, let session,
              let fact = session.company.facts[key],
              let evidence = fact.evidence.first(where: { $0.callID == session.call.id }),
              let segment = session.segments.first(where: { $0.id == evidence.segmentID }),
              let end = segment.sentenceEndedAt else { return }
        renderedVersions[key] = version
        // This observes SwiftUI's update callback, not physical display scan-out.
        renderLatencies.append(max(0, Date().timeIntervalSince(end)))
        if renderLatencies.count > 10000 { renderLatencies.removeFirst(renderLatencies.count - 10000) }
    }
    func collapse(_ group: String) {
        mutate { company, _ in
            FactReducer.setCollapsed(!company.collapsedSections.contains(group), sectionID: group, company: &company); return []
        }
    }
    func accept(_ key: String) {
        mutate { company, config in try FactReducer.acceptProposal(fieldKey: key, configuration: config, company: &company).map { [$0] } ?? [] }
    }
    func dismiss(_ key: String) {
        mutate { company, _ in FactReducer.dismissProposal(fieldKey: key, company: &company); return [] }
    }
    func openHistory(_ call: CallRecord) {
        guard !active, !busy, let database else { return }
        do {
            guard let company = try database.company(id: call.companyID, configurationID: call.configurationID),
                  let config = configurations.filter({ $0.id == call.configurationID }).max(by: { $0.revision < $1.revision }) else { return }
            configuration = config; selectedCompany = company; session = nil; message = nil
            scorecardViewID = UUID()
            firmName = company.name; eventName = call.eventName ?? company.name; showHistory = false
        } catch { message = error.localizedDescription }
    }
    func transcript(for call: CallRecord) -> [TranscriptEntry] {
        (try? database?.segments(callID: call.id, companyID: call.companyID)) ?? []
    }
    func resumeHistory(_ call: CallRecord) async {
        guard !active, !busy, !audioBusy, !starting, !credentialBusy, let database else { return }
        starting = true
        defer { starting = false }
        do {
            guard let company = try database.company(id: call.companyID, configurationID: call.configurationID),
                  let config = configurations.first(where: {
                      $0.id == company.configurationID && $0.revision == company.configurationRevision
                  }) else { throw DatabaseError(message: "The saved call configuration is unavailable.") }
            let running = try ExtractionSession(company: company, call: call, configuration: config,
                database: database, extractor: CloudExtractor(client: await makeClient()))
            running.onChange = { [weak self] in self?.objectWillChange.send() }
            configuration = config; selectedCompany = company; session = running
            scorecardViewID = UUID()
            eventName = call.eventName ?? company.name; firmName = company.name
            message = nil; showHistory = false
            // Recover text only. Audio capture always requires a separate explicit start.
            running.resume()
        } catch { message = error.localizedDescription }
    }
    func refreshHistory() throws {
        history = try database?.calls() ?? []; companies = try database?.companies() ?? []
        pendingCalls = Dictionary(grouping: try database?.pendingJobs() ?? [], by: \.callID).mapValues(\.count)
    }
    func saveRetention() {
        do { try database?.savePreference(transcriptRetentionDays, key: "transcriptRetentionDays") }
        catch { message = error.localizedDescription }
    }
    func saveBudget() {
        guard !active, !busy else { message = "Finish processing before changing the allowance."; return }
        guard apiBudgetUSD.isFinite, apiBudgetUSD >= 0.01, apiBudgetUSD <= 1000 else {
            message = "Set an allowance between $0.01 and $1,000."; return
        }
        do {
            try database?.savePreference(apiBudgetUSD, key: "apiBudgetUSD")
            client = nil; message = nil
        } catch { message = error.localizedDescription }
    }
    func refreshUsage() async {
        do {
            let usage: UsageLedger
            if let client { usage = await client.usage() }
            else {
                let url = try ScorecardDatabase.defaultURL().deletingLastPathComponent().appendingPathComponent("api-usage.json")
                usage = FileManager.default.fileExists(atPath: url.path)
                    ? try JSONDecoder().decode(UsageLedger.self, from: Data(contentsOf: url)) : UsageLedger()
            }
            let audio = usage.requests.filter { $0.endpoint.hasPrefix("realtime_audio") }.reduce(0) { $0 + $1.estimatedUSD }
            let times = session?.measurements.map(\.totalSeconds).sorted() ?? []
            let latency = times.isEmpty ? "No call measurements" :
                String(format: "p95 input-end-to-save %.2fs", times[min(times.count - 1, Int(ceil(Double(times.count) * 0.95)) - 1)])
            usageSummary = String(format: "$%.3f estimated/reserved total · $%.3f audio · $%.2f allowance remaining",
                usage.chargedOrReservedUSD, audio, max(0, apiBudgetUSD - usage.chargedOrReservedUSD)) + "\n" + latency
            if !renderLatencies.isEmpty {
                let sorted = renderLatencies.sorted()
                usageSummary += String(format: "\nVisible-row update callback p95 %.2fs (%d observations)",
                    sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)], sorted.count)
            }
            if usage.chargedOrReservedUSD >= apiBudgetUSD * 0.8 { usageSummary += "\nAt least 80% of the local allowance is used." }
        } catch { usageSummary = "Usage ledger unavailable; requests remain protected by the allowance." }
    }
    func exportCompany(_ call: CallRecord) {
        do {
            guard let company = try database?.company(id: call.companyID, configurationID: call.configurationID) else { return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "company-scorecard.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(company).write(to: url, options: .atomic)
        } catch { message = error.localizedDescription }
    }
    func deleteCompany(_ id: UUID) {
        guard !active, !busy, !audioBusy else { return }
        do {
            try database?.deleteCompany(id)
            if company?.id == id { session = nil; selectedCompany = nil; eventName = ""; firmName = "" }
            try refreshHistory()
        } catch { message = error.localizedDescription }
    }
    func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true // Decode/validate contents after selection; tolerate custom JSON UTIs.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let config = try ScorecardConfiguration.load(Data(contentsOf: url))
            try database?.saveConfiguration(config)
            configurations = try database?.configurations() ?? []
            selectConfiguration(config)
        } catch { message = error.localizedDescription }
    }
    func selectConfiguration(_ config: ScorecardConfiguration) {
        do { try activateConfiguration(config) } catch { message = error.localizedDescription }
    }
    private func activateConfiguration(_ config: ScorecardConfiguration) throws {
        if let session { try session.switchConfiguration(config) }
        try database?.savePreference("\(config.id):\(config.revision)", key: "activeConfiguration")
        configuration = config
        scorecardViewID = UUID()
        if session == nil, let selectedCompany {
            self.selectedCompany = try database?.company(id: selectedCompany.id, configurationID: config.id)
                ?? CompanyScorecard(id: selectedCompany.id, name: selectedCompany.name, configuration: config)
        }
        try refreshHistory()
    }
    func saveEditedConfiguration(_ edited: ScorecardConfiguration) throws {
        guard let database else { throw DatabaseError(message: "Database unavailable.") }
        var revised = edited
        revised.revision = (configurations.filter { $0.id == edited.id }.map(\.revision).max() ?? edited.revision) + 1
        try revised.validate()
        try database.saveConfiguration(revised)
        configurations = try database.configurations()
        try activateConfiguration(revised)
    }
    func exportConfiguration() {
        guard let configuration else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(configuration.id).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ScorecardCoding.encoder().encode(configuration).write(to: url, options: .atomic) }
        catch { message = error.localizedDescription }
    }
    func connectCalendar() async {
        do {
            guard try await calendars.requestFullAccessToEvents() else {
                calendarStatus = "Calendar permission declined; manual Start still works."; return
            }
            let available = calendars.calendars(for: .event)
            calendarStatus = available.isEmpty ? "No calendars. Add Google in Internet Accounts." : "\(available.count) calendars available · manual naming for this version"
        } catch { calendarStatus = "Calendar connection unavailable; manual Start still works." }
    }
    func saveAppearance() {
        do {
            try database?.savePreference(showInScreenSharing, key: "showInScreenSharing")
            try database?.savePreference(opacity, key: "opacity")
            try database?.savePreference(lockShortcut, key: "lockShortcut")
        } catch { message = error.localizedDescription }
    }
    var lockShortcutModifiers: EventModifiers {
        lockShortcut == "controlOptionL" ? [.control, .option] : [.command, .shift]
    }
    func replayFile() async {
        guard !active, !busy, !starting else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true // Decode/validate contents after selection; tolerate custom JSON UTIs.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try ScorecardCoding.decoder().decode(SyntheticCallPack.self, from: Data(contentsOf: url))
            guard let script = pack.calls.first else { throw ConfigurationError.invalid("No synthetic calls in this file.") }
            eventName = script.title; firmName = "Replay \(script.id) \(Date().formatted(date: .omitted, time: .standard))"
            await start(isReplay: true)
            guard let running = session, active else { return }
            let sentences = script.sentences(callID: running.call.id, startingSequence: running.company.latestSequence + 1)
            replaying = true
            replayTask = Task { [weak self] in
                let start = ContinuousClock.now
                do {
                    for (index, var sentence) in sentences.enumerated() {
                        try await ContinuousClock().sleep(until: start + .seconds(index * 5))
                        try Task.checkCancellation()
                        sentence.receivedAt = Date(); sentence.sentenceEndedAt = sentence.receivedAt
                        try running.ingest(sentence)
                        if running.errorMessage != nil { break }
                    }
                    await running.waitUntilIdle()
                    try running.finish()
                } catch is CancellationError {} catch { self?.message = error.localizedDescription }
                self?.replaying = false; try? self?.refreshHistory()
            }
        } catch { message = error.localizedDescription }
    }
}
