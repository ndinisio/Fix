import SwiftUI

/// Where the user supplies a key for one service.
///
/// A `Form` with a secure field, a check that the key actually works, and a way
/// to remove it — the same shape as the account screens people already know
/// from Settings, rather than a bespoke setup flow.
struct APIKeyView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var model: APIKeyViewModel
    @FocusState private var isFieldFocused: Bool

    init(service: CredentialStore.Service) {
        _model = State(initialValue: APIKeyViewModel(service: service))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            if services.buildConfiguration.usesRelay {
                relaySection
            } else {
                keySection(model: model)
                statusSection
                if services.credentials.hasKey(for: model.service) {
                    removeSection
                }
                helpSection
            }
        }
        .navigationTitle(model.service.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isFieldFocused = false
                    Task { await model.save(into: services) }
                }
                .disabled(!model.canSave)
            }
        }
        .task { model.load(from: services.credentials) }
    }

    // MARK: - Sections

    private func keySection(model: APIKeyViewModel) -> some View {
        @Bindable var model = model
        return Section {
            SecureField("Paste your key", text: $model.draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFieldFocused)
                .privacySensitive()
                .accessibilityLabel("\(model.service.providerName) API key")
                .onSubmit {
                    guard model.canSave else { return }
                    Task { await model.save(into: services) }
                }
        } header: {
            Text("\(model.service.providerName) key")
        } footer: {
            Text("Kept in this device's Keychain. It is sent only to \(model.service.providerName), never to FIX, and never leaves this device otherwise.")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch model.state {
            case .idle:
                LabeledContent("Status") {
                    Text(services.credentials.hasKey(for: model.service) ? "Saved" : "Not set")
                        .foregroundStyle(.secondary)
                }
            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking the key…")
                        .foregroundStyle(.secondary)
                }
            case .verified:
                Label("Key accepted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let error):
                VStack(alignment: .leading, spacing: 6) {
                    Label(error.title, systemImage: error.symbolName)
                        .font(.subheadline.weight(.medium))
                    Text(error.guidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .saveFailed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            }
        } footer: {
            Text(model.service.purpose)
        }
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                model.remove(from: services)
            } label: {
                Text("Remove Key")
            }
        }
    }

    @ViewBuilder
    private var helpSection: some View {
        if let url = model.service.consoleURL {
            Section {
                Link(destination: url) {
                    Label("Get a key from \(model.service.providerName)", systemImage: "arrow.up.forward")
                }
            } footer: {
                Text("Opens outside FIX. You will need an account with the provider.")
            }
        }
    }

    private var relaySection: some View {
        Section {
            Label("Configured for this build", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } footer: {
            Text("This build sends requests through a relay that holds the credentials, so no key is needed on the device.")
        }
    }
}

#Preview {
    NavigationStack {
        APIKeyView(service: .ai)
    }
    .environment(PreviewSupport.services)
}
