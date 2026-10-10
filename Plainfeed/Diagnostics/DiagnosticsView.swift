import SwiftUI

/// Read-only by design. Deliberately not called Settings — a page called
/// Settings accretes toggles, and we decided against those (architecture §7.6).
struct DiagnosticsView: View {
    @EnvironmentObject private var diag: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Build") {
                    row("Version", AppVersion.marketing)
                    row("Build", AppVersion.build)
                }

                Section("Current page") {
                    row("Route", diag.currentRoute)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("URL").font(.caption).foregroundStyle(.secondary)
                        Text(diag.currentURL?.absoluteString ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("Assertions") {
                    if diag.assertions.isEmpty {
                        Text("None recorded yet — browse a page.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(diag.assertions) { a in assertionRow(a) }
                    }
                }

                Section {
                    if diag.events.isEmpty {
                        Text("No events.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(diag.events) { e in eventRow(e) }
                    }
                } header: {
                    Text("Events (\(diag.events.count) of \(DiagnosticsStore.maxEvents))")
                } footer: {
                    Text("Kept across launches, so a problem this morning is still here tonight.")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = diag.report()
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy diagnostics",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button(role: .destructive) { diag.clearEvents() } label: {
                        Label("Clear events", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func assertionRow(_ a: AssertionResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon(a.status))
                    .foregroundStyle(colour(a.status))
                Text(a.rule)
                    .font(.system(.caption, design: .monospaced).bold())
                Text(a.name).font(.callout)
            }
            if !a.detail.isEmpty {
                Text(a.detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(a.checkedAt, format: .dateTime.hour().minute().second())
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
    }

    private func eventRow(_ e: DiagEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(e.at, format: .dateTime.hour().minute().second())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(e.source)
                    .font(.system(.caption2, design: .monospaced).bold())
            }
            Text(e.message).font(.caption)
        }
        .padding(.vertical, 1)
    }

    private func icon(_ s: AssertionResult.Status) -> String {
        switch s {
        case .pass:    return "checkmark.circle.fill"
        case .fail:    return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func colour(_ s: AssertionResult.Status) -> Color {
        switch s {
        case .pass:    return .green
        case .fail:    return .orange
        case .skipped: return .secondary
        }
    }
}
