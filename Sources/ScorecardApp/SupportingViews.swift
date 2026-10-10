import SwiftUI
import ScorecardCore

struct ConnectionSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var key = ""
    @State private var testing = false
    @State private var editingConfiguration: ScorecardConfiguration?
    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $key)
                HStack {
                    Button("Save to Keychain") { let enteredKey = key; key = ""; Task { await store.saveKey(enteredKey) } }.disabled(key.isEmpty || store.credentialBusy || store.starting || testing)
                    Button("Remove saved key") { Task { await store.removeKey() } }.disabled(store.credentialBusy || store.starting || testing)
                    Button(testing ? "Testing…" : "Test text APIs") {
                        testing = true
                        Task { await store.testConnection(); testing = false }
                    }.disabled(testing || store.credentialBusy || store.starting)
                }
                Button("Use .env for this session…") { store.importSessionKey() }
                    .disabled(store.active || store.busy || store.starting || store.credentialBusy || testing)
                Text(store.connectionStatus).font(.caption)
                Text("Your key stays on this Mac. The connection test sends a short synthetic example.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio") {
                Picker("Transcription", selection: $store.transcriptionProvider) {
                    Text("OpenAI cloud").tag("openai")
                    Text("Apple Speech on this Mac").tag("apple")
                    Text("Transcript input only").tag("transcript")
                }.disabled(store.audioRunning || store.audioBusy)
                    .onChange(of: store.transcriptionProvider) { _, _ in store.saveAudioSettings() }
                Picker("Meeting browser", selection: $store.browserBundleID) {
                    Text("Google Chrome").tag("com.google.Chrome")
                    Text("Safari").tag("com.apple.Safari")
                    Text("Microsoft Edge").tag("com.microsoft.edgemac")
                    Text("Firefox").tag("org.mozilla.firefox")
                }.disabled(store.audioRunning || store.audioBusy)
                    .onChange(of: store.browserBundleID) { _, _ in store.saveAudioSettings() }
                Text(store.audioStatus).font(.caption)
                HStack {
                    Button("Connect audio") { store.startAudio() }.disabled(!store.active || store.audioRunning || store.audioBusy)
                    Button("Stop audio") { store.stopAudio() }.disabled(!store.audioRunning)
                }
                Text("Capture starts only after Start. Use headphones to keep meeting audio out of your microphone. Apple Speech may download language assets when selected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Calendar · optional") {
                HStack {
                    Button("Connect calendars") { Task { await store.connectCalendar() } }
                    Button("Open Internet Accounts") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.internetaccounts")!)
                    }
                }
                Text(store.calendarStatus).font(.caption)
                Text("Add your Google account in macOS Internet Accounts and enable Calendars. You can always name an event and press Start without connecting Calendar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scorecard configuration") {
                ForEach(store.configurations, id: \.revisionIdentity) { configuration in
                    Button("\(configuration.title) · v\(configuration.revision)") { store.selectConfiguration(configuration) }
                }
                HStack {
                    Button("Import JSON…") { store.importConfiguration() }
                    Button("Export JSON…") { store.exportConfiguration() }
                    Button("Edit fields…") { editingConfiguration = store.configuration }
                }
            }
            Section("Appearance") {
                Toggle("Show in screen sharing", isOn: $store.showInScreenSharing)
                    .onChange(of: store.showInScreenSharing) { _, _ in store.saveAppearance() }
                Slider(value: $store.opacity, in: 0.5...1) { Text("Opacity") }
                    .onChange(of: store.opacity) { _, _ in store.saveAppearance() }
            }
            Section("Testing") {
                Button("Replay synthetic conversation JSON…") { Task { await store.replayFile() } }.disabled(store.active || store.busy)
                Text("Replay sends one sentence every five seconds to OpenAI and uses your API credits.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard shortcuts") {
                Picker("Lock or unlock selected field", selection: $store.lockShortcut) {
                    Text("⌘⇧L · recommended").tag("commandShiftL")
                    Text("⌃⌥L").tag("controlOptionL")
                }.onChange(of: store.lockShortcut) { _, _ in store.saveAppearance() }
                Text("↑ / ↓ selects and edits the next field. Return saves; Escape cancels. ⌘F finds a field. ⌘Z or ⌃Z undoes typing or the last saved manual change.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local data") {
                Picker("Raw transcript retention", selection: $store.transcriptRetentionDays) {
                    Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90); Text("Keep indefinitely").tag(0)
                }.onChange(of: store.transcriptRetentionDays) { _, _ in store.saveRetention() }
                Text("Cleanup runs on launch for finished calls with no pending work. Company answers and evidence stay until you delete the company in History. Local deletion does not delete provider-held processing records.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("API usage") {
                Text(store.usageSummary).font(.caption).textSelection(.enabled)
                HStack {
                    TextField("Cumulative local allowance · USD", value: $store.apiBudgetUSD, format: .number)
                        .disabled(store.active || store.busy)
                    Button("Save allowance") { store.saveBudget() }.disabled(store.active || store.busy)
                    Button("Refresh") { Task { await store.refreshUsage() } }
                }
                Text("Estimated spending since installation, including OpenAI audio. Changing the allowance does not buy credits or alter billing. Reservations may overstate actual usage; check OpenAI billing for final charges.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = store.message { Text(message).foregroundStyle(.orange) }
        }.formStyle(.grouped).frame(width: 580, height: 650)
            .task { await store.refreshUsage() }
            .sheet(item: $editingConfiguration) { config in
                ConfigurationEditor(configuration: config).environmentObject(store)
            }
    }
}
extension ScorecardConfiguration {
    var revisionIdentity: String { "\(id):\(revision)" }
}

struct TranscriptView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var speaker = SpeakerRole.customer
    @State private var debrief = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("TRANSCRIPT").font(.headline); Spacer(); Button("Done") { dismiss() } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.session?.segments ?? []) { segment in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(segment.debrief ? "DEBRIEF" : segment.speaker.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
                            Text(segment.text).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Divider()
            HStack {
                Picker("Speaker", selection: $speaker) {
                    Text("Customer").tag(SpeakerRole.customer); Text("Salesperson").tag(SpeakerRole.salesperson)
                }
                Toggle("Debrief", isOn: $debrief)
            }
            TextEditor(text: $text).frame(height: 85)
            HStack {
                Text("Add transcript or post-call notes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Process") {
                    store.ingest(text: text, speaker: debrief ? .salesperson : speaker, debrief: debrief); text = ""
                }.disabled(store.session == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 560, height: 620)
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedCall: CallRecord?
    @State private var deletingCall: CallRecord?
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("CALL HISTORY").font(.headline); Spacer(); Button("Done") { dismiss() } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.history) { call in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(call.eventName ?? call.companyName)
                                Spacer()
                                if call.isReplay { Text("REPLAY").foregroundStyle(.yellow) }
                            }
                            Text("\(call.companyName) · \(call.startedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Company answers") { store.openHistory(call) }.disabled(store.active || store.busy)
                                Button("Transcript") { selectedCall = call }
                                Menu("More") {
                                    Button("Export company JSON…") { store.exportCompany(call) }
                                    Button("Delete company and all calls…", role: .destructive) { deletingCall = call }
                                        .disabled(store.active || store.busy || store.audioBusy)
                                }
                                if let pending = store.pendingCalls[call.id], pending > 0 {
                                    Button("Resume \(pending) pending") { Task { await store.resumeHistory(call) } }
                                        .disabled(store.active || store.busy || store.audioBusy)
                                }
                            }
                        }.padding(.vertical, 5).accessibilityElement(children: .contain)
                        Divider()
                    }
                }
            }
        }.padding(20).frame(width: 560, height: 550)
            .onAppear { try? store.refreshHistory() }
            .confirmationDialog("Delete this company and every associated call?", isPresented: Binding(
                get: { deletingCall != nil }, set: { if !$0 { deletingCall = nil } }), titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) {
                    if let call = deletingCall { store.deleteCompany(call.companyID) }
                    deletingCall = nil
                }
                Button("Cancel", role: .cancel) { deletingCall = nil }
            } message: {
                Text("This removes \(deletingCall?.companyName ?? "the company"), its answers, transcripts, evidence, pending jobs, and all call history from this Mac.")
            }
            .sheet(item: $selectedCall) { call in
                VStack(alignment: .leading) {
                    HStack { Text(call.eventName ?? call.companyName); Spacer(); Button("Done") { selectedCall = nil } }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(store.transcript(for: call)) { segment in
                                Text("\(segment.speaker.rawValue.uppercased()): \(segment.text)").textSelection(.enabled)
                            }
                        }
                    }
                }.padding(20).frame(width: 540, height: 550)
            }
    }
}
