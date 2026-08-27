import SwiftUI

/// Choosing which model answers diagnoses.
///
/// The list comes from the provider rather than from a constant in the app: a
/// model named in code is correct only until that model is retired, and the
/// failure when it is — a refused request — explains itself badly.
struct ModelPickerView: View {
    @Environment(ServiceContainer.self) private var services

    @State private var models: [String] = []
    @State private var state: LoadState = .loading

    private enum LoadState: Equatable {
        case loading
        case loaded
        case failed(APIError)
    }

    var body: some View {
        List {
            switch state {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Asking the provider…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let error):
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error.title, systemImage: error.symbolName)
                            .font(.subheadline.weight(.medium))
                        Text(error.guidance)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Try Again") {
                        Task { await load() }
                    }
                }
            case .loaded:
                Section {
                    ForEach(models, id: \.self) { model in
                        Button {
                            select(model)
                        } label: {
                            HStack {
                                Text(model)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if model == services.configuration.groqModel {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .accessibilityAddTraits(
                            model == services.configuration.groqModel ? [.isSelected] : []
                        )
                    }
                } footer: {
                    Text("Listed by the provider for this key. A larger model reasons better; a smaller one answers faster.")
                }
            }
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func select(_ model: String) {
        services.settings.groqModel = model
        services.credentialsDidChange()
    }

    private func load() async {
        guard let transport = services.configuration.ai else {
            state = .failed(.notConfigured)
            return
        }
        state = .loading
        do {
            models = try await GroqService(
                transport: transport, model: services.configuration.groqModel
            ).availableModels()
            state = models.isEmpty ? .failed(.invalidResponse) : .loaded
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.underlying(description: "The model list couldn't be loaded."))
        }
    }
}
