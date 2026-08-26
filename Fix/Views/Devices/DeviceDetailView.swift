import SwiftData
import SwiftUI

/// A device's page: how to keep it working, what has gone wrong before, and a
/// way straight into a new diagnosis.
struct DeviceDetailView: View {
    let device: SavedDevice

    @Environment(ServiceContainer.self) private var services
    @Environment(Library.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var model = DeviceCareViewModel()
    @State private var isConfirmingDelete = false
    @State private var pastSessions: [StoredSession] = []

    var body: some View {
        List {
            Section {
                Button {
                    router.troubleshoot(device: device.name)
                } label: {
                    Label("Troubleshoot This Device", systemImage: "stethoscope")
                }
            }

            careSection
            historySection
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { pastSessions = library.sessions(forDevice: device.name) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if device.carePlan != nil {
                        Button {
                            Task { await load() }
                        } label: {
                            Label("Refresh Care Guidance", systemImage: "arrow.clockwise")
                        }
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Device", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete \(device.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Device", role: .destructive) {
                library.delete(device)
                dismiss()
            }
        } message: {
            Text("Its care guidance is removed. History is kept.")
        }
    }

    // MARK: - Care

    @ViewBuilder
    private var careSection: some View {
        if let plan = device.carePlan {
            Section {
                Text(plan.summary)
                    .font(.subheadline)
                ForEach(plan.tips) { tip in
                    CareTipRow(tip: tip)
                }
            } header: {
                Text("Keeping it healthy")
            } footer: {
                Text("Generated \(plan.generatedAt.formatted(date: .abbreviated, time: .omitted)). Available offline.")
            }

            if !plan.signsToWatch.isEmpty {
                Section("Signs to watch for") {
                    ForEach(plan.signsToWatch, id: \.self) { sign in
                        Label(sign, systemImage: "circle.fill")
                            .labelStyle(.bullet)
                            .font(.subheadline)
                    }
                }
            }
        } else {
            Section {
                switch model.state {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Putting together care guidance…")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let error):
                    VStack(alignment: .leading, spacing: 10) {
                        Label(error.guidance, systemImage: error.symbolName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if error.isRetryable {
                            Button("Try Again") {
                                Task { await load() }
                            }
                        }
                    }
                case .idle:
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Get Care Guidance", systemImage: "sparkles")
                    }
                }
            } header: {
                Text("Keeping it healthy")
            } footer: {
                Text("Maintenance advice for this device, saved here so it stays available offline.")
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        if !pastSessions.isEmpty {
            Section("Past problems") {
                ForEach(pastSessions) { stored in
                    NavigationLink(value: stored) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stored.problem)
                                .font(.subheadline)
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(stored.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                if stored.isSolved {
                                    Text("· Solved")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        await model.loadCarePlan(for: device, services: services, library: library)
    }
}
