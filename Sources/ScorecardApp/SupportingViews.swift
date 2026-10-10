import SwiftUI
import ScorecardCore

struct ConnectionSettings: View {
    @EnvironmentObject var store: AppStore
    @State private var key = ""
    @State private var testing = false
    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $key)
                HStack {
                    Button("Save to Keychain") { store.saveKey(key); key = "" }.disabled(key.isEmpty)
                    Button("Remove saved key") { store.removeKey() }
                    Button(testing ? "Testing…" : "Test text APIs") {
                        testing = true
                        Task { await store.testConnection(); testing = false }
                    }.disabled(testing)
                }
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
                        .disabled(store.active || store.busy)
                }
                HStack {
                    Button("Import JSON…") { store.importConfiguration() }.disabled(store.active || store.busy)
                    Button("Export JSON…") { store.exportConfiguration() }
                }
            }
            Section("Appearance") {
                Toggle("Show in screen sharing", isOn: $store.showInScreenSharing)
                    .onChange(of: store.showInScreenSharing) { _, _ in store.saveAppearance() }
                Slider(value: $store.opacity, in: 0.5...1) { Text("Opacity") }
                    .onChange(of: store.opacity) { _, _ in store.saveAppearance() }
            }
            Section("Testing") {
                Button("Replay synthetic conversation JSON…") { store.replayFile() }.disabled(store.active || store.busy)
                Text("Replay sends one sentence every five seconds to OpenAI and uses your API credits.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = store.message { Text(message).foregroundStyle(.orange) }
        }.formStyle(.grouped).frame(width: 580, height: 650)
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
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("CALL HISTORY").font(.headline); Spacer(); Button("Done") { dismiss() } }
            List(store.history) { call in
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
                    }
                }.padding(.vertical, 5)
            }
        }.padding(20).frame(width: 560, height: 550)
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
