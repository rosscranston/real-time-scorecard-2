import SwiftUI
import ScorecardCore

struct ScorecardView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedField: String?
    @State private var editTarget: String?
    @State private var searching = false
    @State private var findQuery = ""
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            header.padding(12)
            if searching {
                TextField("Find a field", text: $findQuery).textFieldStyle(.plain)
                    .focused($searchFocused).padding(.horizontal, 12).padding(.bottom, 8)
                    .onSubmit { findField() }
                    .onExitCommand { searching = false }
            }
            Divider().overlay(scoreGreen.opacity(0.25))
            if let config = store.configuration {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(config.orderedGroups(for: store.callType)) { group in
                            section(group, configuration: config)
                        }
                    }.padding(10)
                }.onChange(of: selectedField) { _, field in
                    if let field { proxy.scrollTo(field, anchor: .center) }
                }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button { store.showHistory = true } label: { Image(systemName: "clock") }.help("Call history")
                Button { store.showTranscript = true } label: { Image(systemName: "text.alignleft") }.help("Transcript and debrief")
                Spacer()
                if store.session?.call.isReplay == true { Text("REPLAY").foregroundStyle(.yellow) }
                if store.busy { ProgressView().controlSize(.mini) }
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            }.padding(12)
            if let error = store.message ?? store.session?.errorMessage {
                HStack(alignment: .top) {
                    Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { Task { await store.retry() } }.disabled(store.session == nil)
                }.padding(10)
            }
        }
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(scoreGreen)
        .background(.black.opacity(store.opacity)).frame(minWidth: 270, minHeight: 480)
        .background(WindowPolicy(showInSharing: store.showInScreenSharing, opacity: store.opacity))
        .sheet(isPresented: $store.showTranscript) { TranscriptView().environmentObject(store) }
        .sheet(isPresented: $store.showHistory) { HistoryView().environmentObject(store) }
        .onChange(of: store.scorecardViewID) { _, _ in
            selectedField = nil; editTarget = nil; searching = false
        }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .background {
            Group {
                Button("") { if let selectedField { store.toggleLock(selectedField) } }
                    .keyboardShortcut("l", modifiers: store.lockShortcutModifiers)
                Button("") { searching = true; searchFocused = true }.keyboardShortcut("f")
            }.hidden()
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIVE SCORECARD").tracking(1)
                Spacer()
                Circle().fill(store.active ? scoreGreen : Color.gray).frame(width: 5, height: 5)
            }
            if store.active {
                HStack {
                    Text(store.session?.call.eventName ?? "").lineLimit(1)
                    Spacer()
                    Button("Stop") { store.stop() }
                }
            } else {
                TextField("Event name", text: $store.eventName).textFieldStyle(.plain)
                HStack {
                    TextField("Firm (optional)", text: $store.firmName).textFieldStyle(.plain)
                    Button(store.starting ? "Connecting…" : "Start") { Task { await store.start() } }.disabled(store.eventName.trimmingCharacters(in: .whitespaces).isEmpty || store.busy || store.audioBusy || store.starting || store.credentialBusy)
                }
            }
            Picker("Call type", selection: $store.callType) {
                Text("Initial").tag("initial"); Text("Demo").tag("demo"); Text("Review").tag("review")
            }.labelsHidden().pickerStyle(.segmented)
            if store.active && store.session?.call.isReplay != true {
                Text(store.audioStatus).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
    private func section(_ group: FieldGroup, configuration: ScorecardConfiguration) -> some View {
        let collapsed = store.company?.collapsedSections.contains(group.id) == true
        let count = store.company?.unreadFields[group.id]?.count ?? 0
        let conflicts = group.fields.contains { store.company?.facts[$0.key]?.proposal != nil }
        return VStack(spacing: 0) {
            Button { store.collapse(group.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8))
                    Text(group.label.uppercased()).tracking(0.8)
                    Spacer()
                    if collapsed && count > 0 { Text("\(count)").foregroundStyle(.white) }
                    if conflicts { Text("!").foregroundStyle(.orange) }
                }.padding(.vertical, 9)
            }.buttonStyle(.plain)
            if !collapsed {
                ForEach(group.fields.filter(\.isVisible)) { field in
                    ScorecardRow(field: field, configuration: configuration, selected: selectedField == field.key,
                                 editRequested: editTarget == field.key,
                                 select: { selectedField = field.key },
                                 navigate: { moveSelection($0) }).environmentObject(store).id(field.key)
                }
            }
        }
    }
    private func moveSelection(_ delta: Int) {
        guard let config = store.configuration else { return }
        let fields = config.orderedGroups(for: store.callType)
            .filter { store.company?.collapsedSections.contains($0.id) != true }.flatMap(\.fields).filter(\.isVisible)
        guard !fields.isEmpty else { return }
        let current = fields.firstIndex { $0.key == selectedField } ?? (delta > 0 ? -1 : fields.count)
        selectedField = fields[max(0, min(fields.count - 1, current + delta))].key
        editTarget = selectedField
    }
    private func findField() {
        guard let config = store.configuration, !findQuery.isEmpty else { return }
        for group in config.orderedGroups(for: store.callType) {
            if let field = group.fields.first(where: { $0.isVisible && $0.label.localizedCaseInsensitiveContains(findQuery) }) {
                if store.company?.collapsedSections.contains(group.id) == true { store.collapse(group.id) }
                searching = false; selectedField = field.key; editTarget = field.key
                return
            }
        }
    }
}

struct ScorecardRow: View {
    @EnvironmentObject var store: AppStore
    let field: FieldDefinition
    let configuration: ScorecardConfiguration
    var selected: Bool
    var editRequested: Bool
    var select: () -> Void
    var navigate: (Int) -> Void
    @State private var editing = false
    @State private var draft = ""
    @State private var editContext: UUID?
    @State private var evidenceOpen = false
    @State private var proposalOpen = false
    @State private var hover = false
    @State private var justUpdated = false
    @State private var highlightTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    private var record: FactRecord? { store.company?.facts[field.key] }
    private var fact: FactRecord? { FactReducer.displayedFact(record, field: field) }
    private var sourceColor: Color {
        switch fact?.evidence.first?.source {
        case .call: return .green
        case .calendar: return .yellow
        case .email: return .blue
        case .manual: return .purple
        case .calculated: return .cyan
        case nil: return .clear
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(sourceColor).frame(width: 4, height: 4).help(fact?.evidence.first?.source.rawValue ?? "")
                Text(field.label.uppercased()).foregroundStyle(.gray).lineLimit(1).frame(maxWidth: 105, alignment: .leading)
                    .help(field.label)
                if editing {
                    TextField("", text: $draft).textFieldStyle(.plain).focused($focused)
                        .task { await Task.yield(); if !Task.isCancelled { focused = true } }
                        .onSubmit { commitEdit() }
                        .onExitCommand { editing = false }
                        .onKeyPress(.upArrow) { commitEdit(); navigate(-1); return .handled }
                        .onKeyPress(.downArrow) { commitEdit(); navigate(1); return .handled }
                        .onChange(of: focused) { _, focus in
                            if !focus && editing { commitEdit() }
                        }
                } else {
                    Text(fact?.display ?? "?")
                        .foregroundStyle(fact == nil ? .yellow : ((fact?.confidence ?? 0) < configuration.thresholds(for: field).initial ? .red : scoreGreen))
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle()).onTapGesture { select(); beginEdit() }
                        .onHover { hover = $0 && fact != nil }
                        .popover(isPresented: $hover, arrowEdge: .bottom) {
                            Text(fact?.display ?? "").font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled).padding().frame(maxWidth: 400)
                        }
                }
                if record?.proposal != nil {
                    Button("!") { proposalOpen.toggle() }.foregroundStyle(.orange)
                        .popover(isPresented: $proposalOpen) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(record?.proposal?.value.display ?? "")
                                ForEach(Array((record?.proposal?.evidence ?? []).enumerated()), id: \.offset) { _, evidence in Text(evidence.quote) }
                                HStack {
                                    Button("Accept & keep locked") { store.accept(field.key); proposalOpen = false }
                                    Button("Dismiss") { store.dismiss(field.key); proposalOpen = false }
                                }
                            }.padding().frame(width: 320)
                        }
                }
                Button { select(); store.toggleLock(field.key) } label: {
                    Image(systemName: record?.locked == true ? "lock.fill" : "lock.open")
                        .foregroundStyle(record?.locked == true ? scoreGreen : .gray.opacity(0.45))
                }.help(record?.locked == true ? "Unlock" : "Lock")
                Button(evidenceOpen ? "−" : "+") { evidenceOpen.toggle() }
                    .foregroundStyle(.gray).disabled(record?.evidence.isEmpty ?? true).help("Evidence")
            }.padding(.vertical, 6).padding(.horizontal, 3)
                .background(selected ? scoreGreen.opacity(0.10) : (justUpdated ? scoreGreen.opacity(0.07) : .clear))
                .contentShape(Rectangle()).onTapGesture { select(); beginEdit() }
            if evidenceOpen {
                ForEach(Array((record?.evidence ?? []).enumerated()), id: \.offset) { _, evidence in
                    Text(evidence.quote).foregroundStyle(.gray).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).padding(.leading, 12).padding(.bottom, 6)
                }
            }
        }.buttonStyle(.plain)
        .onChange(of: editRequested) { _, requested in
            if requested { beginEdit() }
        }
        .onChange(of: selected) { _, selected in
            if selected { beginEdit() }
        }
        .onAppear { if editRequested { beginEdit() } }
        .onChange(of: record?.version) { old, current in
            guard let current, old != current else { return }
            store.recordVisibleUpdate(field.key, version: current)
            justUpdated = true; highlightTask?.cancel()
            highlightTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                if !Task.isCancelled { justUpdated = false }
            }
        }
        .onDisappear { highlightTask?.cancel() }
        .onChange(of: store.scorecardViewID) { _, _ in
            evidenceOpen = false; proposalOpen = false; editing = false; focused = false; hover = false
            highlightTask?.cancel(); justUpdated = false
        }
        .contextMenu {
            Button("Edit") { select(); beginEdit() }
            Button(record?.locked == true ? "Unlock" : "Lock") { store.toggleLock(field.key) }
            if let options = field.options {
                ForEach(options.filter { $0 != "Other" }, id: \.self) { option in Button(option) { store.edit(field, text: option) } }
            }
            Button("Clear") { store.mutate { company, config in [FactReducer.clear(fieldKey: field.key, configuration: config, company: &company)] } }
        }.disabled(store.company == nil)
    }
    private func beginEdit() {
        editContext = store.scorecardViewID
        draft = fact?.display ?? ""; editing = true; focused = true
    }
    private func commitEdit() {
        guard editing else { return }
        editing = false
        guard editContext == store.scorecardViewID else { return }
        // Merely navigating through a field must not create a lock or clear it.
        guard draft != (fact?.display ?? "") else { return }
        store.edit(field, text: draft)
    }
}

struct WindowPolicy: NSViewRepresentable {
    var showInSharing: Bool
    var opacity: Double
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.sharingType = showInSharing ? .readOnly : .none
            window.level = .floating; window.isOpaque = false
            window.backgroundColor = .black.withAlphaComponent(opacity)
        }
    }
}
