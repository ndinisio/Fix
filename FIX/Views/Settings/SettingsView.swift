import SwiftData
import SwiftUI

/// A short settings screen: what FIX is connected to, what it keeps, and what
/// it sends. Nothing here exists to fill space.
struct SettingsView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @Query private var devices: [SavedDevice]
    @Query private var sessions: [StoredSession]

    @State private var isConfirmingClearHistory = false
    @State private var isConfirmingClearDevices = false

    var body: some View {
        @Bindable var settings = services.settings

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Diagnosis") {
                        StatusLabel(isConfigured: services.configuration.isAIConfigured)
                    }
                    LabeledContent("Video search") {
                        StatusLabel(isConfigured: services.configuration.isVideoSearchConfigured)
                    }
                    Toggle("Include repair videos", isOn: $settings.includeVideos)
                        .disabled(!services.configuration.isVideoSearchConfigured)
                } header: {
                    Text("Services")
                } footer: {
                    Text(servicesFooter)
                }

                if library.isEphemeral {
                    Section {
                        Label(
                            "History and saved devices won't be kept after you close FIX.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    } header: {
                        Text("Storage")
                    } footer: {
                        Text("FIX couldn't open its data store, so it's using temporary storage for now.")
                    }
                }

                Section("Data") {
                    Button(role: .destructive) {
                        isConfirmingClearHistory = true
                    } label: {
                        Text("Clear History")
                    }
                    .disabled(sessions.isEmpty)

                    Button(role: .destructive) {
                        isConfirmingClearDevices = true
                    } label: {
                        Text("Remove All Devices")
                    }
                    .disabled(devices.isEmpty)
                }

                Section {
                    NavigationLink("Privacy") { PrivacyView() }
                    LabeledContent("Version", value: Self.versionString)
                } header: {
                    Text("About")
                } footer: {
                    Text("FIX diagnoses device problems and helps you keep what you own working for longer.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear all history?",
                isPresented: $isConfirmingClearHistory,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) { library.deleteAllSessions() }
            } message: {
                Text("This removes every saved diagnosis.")
            }
            .confirmationDialog(
                "Remove all saved devices?",
                isPresented: $isConfirmingClearDevices,
                titleVisibility: .visible
            ) {
                Button("Remove All Devices", role: .destructive) { library.deleteAllDevices() }
            } message: {
                Text("Their care guidance is removed too. History is kept.")
            }
        }
    }

    private var servicesFooter: String {
        if services.configuration.isAIConfigured {
            "Diagnosis runs on a service configured for this build. Turning videos off saves a request per diagnosis."
        } else {
            "No AI provider is configured, so new diagnoses aren't available. History and saved devices still work."
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Configured or not, said with a symbol and a word — never colour alone.
private struct StatusLabel: View {
    let isConfigured: Bool

    var body: some View {
        Label(
            isConfigured ? "Ready" : "Not configured",
            systemImage: isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
        .foregroundStyle(isConfigured ? .secondary : .primary)
    }
}

#Preview {
    SettingsView()
        .environment(PreviewSupport.services)
        .environment(PreviewSupport.library)
        .modelContainer(PreviewSupport.container)
}
