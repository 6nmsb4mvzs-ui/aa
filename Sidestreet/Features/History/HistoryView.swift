import SwiftUI

/// Previously searched cities and areas (stored only on this iPhone).
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    var onRestore: () -> Void
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if model.historyEntries.isEmpty {
                    StateMessage(systemImage: "clock.arrow.circlepath", title: "No searches yet",
                                 message: "Cities and areas you explore appear here, so you can jump back in. History never leaves this iPhone.")
                } else {
                    List {
                        ForEach(model.historyEntries) { entry in
                            Button {
                                Task {
                                    await model.restore(entry)
                                    onRestore()
                                }
                            } label: {
                                HistoryRow(entry: entry)
                            }
                            .listRowBackground(Theme.surfaceRaised)
                        }
                        .onDelete { offsets in
                            let entries = offsets.map { model.historyEntries[$0] }
                            Task { for entry in entries { await model.deleteHistory(entry) } }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle("History")
            .toolbar {
                if !model.historyEntries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Clear all search history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { Task { await model.clearHistory() } }
            }
        }
    }
}

private struct HistoryRow: View {
    @Environment(AppSettings.self) private var settings
    var entry: SearchHistoryEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.centerSource == .gps ? "location.fill" : "building.2")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.label).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text([entry.subtitle, Format.radius(entry.radiusMeters, metric: settings.useMetric) + " radius",
                      "\(entry.resultCount) results"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if !entry.filters.isEmpty {
                    Text(entry.filters.map(\.title).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Format.relative(entry.date)).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 4)
    }
}
