import SwiftData
import SwiftUI

/// Everything FIX has diagnosed, newest first, grouped by day.
///
/// Reads with `@Query`, so the list updates itself as sessions are saved. It
/// works with no connection: past answers are stored in full.
struct HistoryView: View {
    @Environment(Library.self) private var library

    @Query(sort: \StoredSession.updatedAt, order: .reverse)
    private var sessions: [StoredSession]

    @State private var searchText = ""
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No History", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Problems you diagnose appear here, and stay readable offline.")
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Devices and problems")
            .toolbar {
                if !sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        // In a menu rather than as a bare button: clearing
                        // everything should take one deliberate step more than
                        // a mis-tap on the navigation bar.
                        Menu {
                            Button(role: .destructive) {
                                isConfirmingClear = true
                            } label: {
                                Label("Clear History", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear all history?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    library.deleteAllSessions()
                }
            } message: {
                Text("This removes every saved diagnosis. Saved devices are kept.")
            }
            .navigationDestination(for: StoredSession.self) { stored in
                StoredSessionDestination(stored: stored)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sessions) { stored in
                        NavigationLink(value: stored) {
                            HistoryRow(stored: stored)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            library.delete(group.sessions[index])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grouping

    private var filtered: [StoredSession] {
        guard let needle = searchText.nilIfBlank?.lowercased() else { return sessions }
        return sessions.filter {
            $0.device.lowercased().contains(needle) || $0.problem.lowercased().contains(needle)
        }
    }

    private struct DayGroup {
        let title: String
        let sessions: [StoredSession]
    }

    /// Today, Yesterday, then month and year — the same shape as Messages or
    /// Mail, rather than a flat list of timestamps.
    private var groups: [DayGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [StoredSession]] = [:]

        for session in filtered {
            let title = Self.groupTitle(for: session.updatedAt, calendar: calendar)
            if buckets[title] == nil {
                buckets[title] = []
                order.append(title)
            }
            buckets[title]?.append(session)
        }
        return order.map { DayGroup(title: $0, sessions: buckets[$0] ?? []) }
    }

    static func groupTitle(for date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -7, to: now), date > week {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

/// One row of history: device, problem, when, and whether it was solved.
struct HistoryRow: View {
    let stored: StoredSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stored.category.symbolName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(stored.device)
                    .font(.headline)
                Text(stored.problem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(stored.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if stored.isSolved {
                        Text("·")
                        Label("Solved", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HistoryView()
        .environment(PreviewSupport.services)
        .environment(PreviewSupport.library)
        .modelContainer(PreviewSupport.container)
}
