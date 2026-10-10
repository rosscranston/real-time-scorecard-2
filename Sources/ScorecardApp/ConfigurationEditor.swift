import SwiftUI
import ScorecardCore

struct ConfigurationEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScorecardConfiguration
    @State private var selected: String?
    @State private var error: String?
    init(configuration: ScorecardConfiguration) {
        _draft = State(initialValue: configuration)
        _selected = State(initialValue: configuration.fields.first?.key)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(draft.title) · \(draft.fields.count) fields").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save revision") {
                    do { try store.saveEditedConfiguration(draft); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
            Text("Changes create a new saved revision. Export JSON includes your edits; previous revisions remain available.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(draft.groups) { group in
                        Section(group.label) {
                            ForEach(group.fields) { field in Text(field.label).tag(field.key) }
                        }
                    }
                }.frame(width: 190)
                if let location = selectedLocation {
                    FieldSettingsEditor(field: $draft.groups[location.group].fields[location.field],
                                        defaults: draft.thresholds(for: draft.groups[location.group].fields[location.field]))
                        .id(selected)
                }
            }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(18).frame(width: 780, height: 650)
    }
    private var selectedLocation: (group: Int, field: Int)? {
        for g in draft.groups.indices {
            if let f = draft.groups[g].fields.firstIndex(where: { $0.key == selected }) { return (g, f) }
        }
        return nil
    }
}

private struct FieldSettingsEditor: View {
    @Binding var field: FieldDefinition
    let defaults: ConfidenceThresholds
    @State private var options = ""
    @State private var aliases = ""
    @State private var aliasError: String?
    private var thresholds: ConfidenceThresholds { field.confidence ?? defaults }
    var body: some View {
        Form {
            TextField("Label", text: $field.label)
            Toggle("Visible", isOn: Binding(get: { field.isVisible }, set: { field.visible = $0 }))
            Toggle("Extract automatically", isOn: Binding(get: { field.isAutomatic }, set: { field.automaticExtraction = $0 }))
            Picker("Who can supply the answer", selection: Binding(get: { field.sourcePolicy ?? "either" }, set: { field.sourcePolicy = $0 })) {
                Text("Either speaker").tag("either")
                Text("Customer").tag("customer")
                Text("Salesperson").tag("salesperson")
            }
            Text("Salesperson debrief can supply any field.").font(.caption).foregroundStyle(.secondary)
            TextField("Evidence rule", text: Binding(get: { field.evidenceRule ?? "" }, set: { field.evidenceRule = $0 }), axis: .vertical)
                .lineLimit(3...6)
            if field.type == "select" {
                Section("Allowed values · one per line") {
                    TextEditor(text: $options).font(.system(.body, design: .monospaced)).frame(height: 110)
                        .onChange(of: options) { _, text in
                            field.options = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        }
                    Text("Include Other to capture a named value outside the list.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Spelling examples · canonical value = alias, alias") {
                    TextEditor(text: $aliases).font(.system(.body, design: .monospaced)).frame(height: 80)
                        .onChange(of: aliases) { _, text in updateAliases(text) }
                    if let aliasError { Text(aliasError).foregroundStyle(.orange).font(.caption) }
                }
            }
            Section("Confidence thresholds") {
                threshold("Show tentative answer", path: \.tentative)
                threshold("Show normal answer", path: \.initial)
                threshold("Replace existing answer", path: \.replacement)
                Text("Model confidence is a heuristic. Tentative ≤ normal ≤ replacement; low confidence answers appear red.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .onAppear {
                options = (field.options ?? []).joined(separator: "\n")
                aliases = (field.aliases ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value.joined(separator: ", "))" }.joined(separator: "\n")
            }
    }
    private func threshold(_ title: String, path: WritableKeyPath<ConfidenceThresholds, Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: Binding(get: { thresholds[keyPath: path] }, set: { value in
                var next = thresholds; next[keyPath: path] = value; next.calibrated = false; field.confidence = next
            }), format: .number.precision(.fractionLength(2))).frame(width: 65)
        }
    }
    private func updateAliases(_ text: String) {
        var parsed: [String: [String]] = [:]
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else {
                aliasError = "Use canonical value = alias, alias."
                // Leave an invalid target so Save reports validation instead of dropping an edit.
                field.aliases = ["": []]; return
            }
            parsed[parts[0]] = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        aliasError = nil; field.aliases = parsed
    }
}
