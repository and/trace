import SwiftUI
import SwiftData

/// The screen the app opens on: today's heart rate with activity bands, then
/// the controls to log one, then what was logged recently.
struct HomeView: View {
    @ObservedObject var health: HealthStore
    @Environment(\.modelContext) private var context
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]

    @State private var customLabel = ""
    @State private var editing: Activity?
    @State private var addingCustom = false

    private var running: Activity? { activities.first { $0.isRunning } }
    private var finished: [Activity] { activities.filter { !$0.isRunning } }

    /// Built-in labels plus every label typed before, most recent first.
    private var quickPicks: [String] {
        var seen = Set(QuickLabel.all)
        var remembered: [String] = []
        for activity in activities where !seen.contains(activity.label) {
            seen.insert(activity.label)
            remembered.append(activity.label)
        }
        return QuickLabel.all + remembered
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayView(health: health)
                        .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                Section {
                    if let running {
                        RunningRow(activity: running) { running.end = .now }
                    } else {
                        picker
                    }
                }

                if !finished.isEmpty {
                    Section("Recent") {
                        ForEach(finished) { activity in
                            Button { editing = activity } label: {
                                LoggedRow(activity: activity)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    context.delete(activity)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if !finished.isEmpty { EditButton() } }
            .sheet(item: $editing) { ActivityEditor(activity: $0) }
            .alert("New activity", isPresented: $addingCustom) {
                TextField("Name", text: $customLabel)
                Button("Start") { start(customLabel) }
                Button("Cancel", role: .cancel) { customLabel = "" }
            }
        }
    }

    /// A single scrolling row of chips, so the chart keeps the screen.
    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickPicks, id: \.self) { label in
                    Button(label) { start(label) }
                        .buttonStyle(.bordered)
                }
                Button {
                    addingCustom = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func start(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(Activity(label: trimmed))
        customLabel = ""
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(finished[index]) }
    }
}

// MARK: - Editing

struct ActivityEditor: View {
    @Bindable var activity: Activity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Label", text: $activity.label)
                }
                Section("Note") {
                    TextField("Optional", text: $activity.note, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Time") {
                    DatePicker("Start", selection: $activity.start)
                    // A running activity has no end yet; binding through a
                    // non-optional proxy would silently stop it.
                    if activity.end != nil {
                        DatePicker("End", selection: Binding(
                            get: { activity.end ?? activity.start },
                            set: { activity.end = $0 }
                        ))
                    }
                }
                Section {
                    Button("Delete Activity", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete this activity?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    // Dismiss before deleting: the sheet is bound to this
                    // object, and tearing it out from under the view first
                    // leaves @Bindable pointing at a deleted model.
                    dismiss()
                    context.delete(activity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rows

private struct RunningRow: View {
    let activity: Activity
    let onStop: () -> Void

    var body: some View {
        // TimelineView keeps the elapsed label ticking without a manual timer.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                VStack(alignment: .leading) {
                    Text(activity.label).font(.headline)
                    Text(activity.duration.elapsedDescription)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop", action: onStop)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct LoggedRow: View {
    let activity: Activity

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(activity.label)
                Text(activity.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(activity.duration.elapsedDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

extension TimeInterval {
    var elapsedDescription: String {
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm %02ds", m, s)
    }
}
