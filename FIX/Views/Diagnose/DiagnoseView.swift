import SwiftUI

/// The app's front door: a device, a problem, and one action.
///
/// A `Form` rather than a bespoke layout — it brings the right field spacing,
/// grouping, keyboard handling and Dynamic Type behaviour for nothing, and it
/// is what someone would expect to find in an app that asks them two questions.
struct DiagnoseView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(Library.self) private var library
    @Environment(AppRouter.self) private var router

    @State private var model = DiagnoseViewModel()
    @State private var activeSession: SessionViewModel?
    @State private var isShowingSettings = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case device, problem
    }

    var body: some View {
        NavigationStack {
            Form {
                deviceSection
                problemSection
                detailsSection
            }
            .navigationTitle("Diagnose")
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { actionBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .navigationDestination(item: $activeSession) { session in
                SessionView(model: session)
            }
            .task {
                model.refreshRecents(from: library)
            }
            .onChange(of: router.pendingDevice) { _, newValue in
                guard newValue != nil, let device = router.consumePendingDevice() else { return }
                model.device = device
                focusedField = .problem
            }
        }
    }

    // MARK: - Sections

    private var deviceSection: some View {
        @Bindable var model = model
        return Section {
            TextField("iPhone 15, PS5, Bambu Lab A1…", text: $model.device)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .device)
                .onSubmit { focusedField = .problem }
                .accessibilityLabel("Device")

            if focusedField == .device {
                ForEach(model.suggestions) { suggestion in
                    DeviceSuggestionRow(suggestion: suggestion) {
                        model.apply(suggestion: suggestion)
                        focusedField = .problem
                    }
                }
            }
        } header: {
            Text("Device")
        }
        .animation(.default, value: focusedField)
        .animation(.default, value: model.suggestions)
    }

    private var problemSection: some View {
        @Bindable var model = model
        return Section {
            TextField("Describe what's happening…", text: $model.problem, axis: .vertical)
                .lineLimit(4...12)
                .focused($focusedField, equals: .problem)
                .accessibilityLabel("Problem")
        } header: {
            Text("Problem")
        } footer: {
            Text("What it does, when it started, and anything you've already tried.")
        }
    }

    private var detailsSection: some View {
        @Bindable var model = model
        return Section {
            DisclosureGroup("Add details", isExpanded: $model.isShowingDetails) {
                Picker("Started", selection: $model.details.onset) {
                    Text("Not specified").tag(ProblemDetails.Onset?.none)
                    ForEach(ProblemDetails.Onset.allCases) { onset in
                        Text(onset.title).tag(ProblemDetails.Onset?.some(onset))
                    }
                }
                TextField("Error message", text: $model.details.errorMessage.orEmpty, axis: .vertical)
                    .lineLimit(1...4)
                TextField("Already tried", text: $model.details.alreadyTried.orEmpty, axis: .vertical)
                    .lineLimit(1...4)
            }
        } footer: {
            Text("Optional. FIX works without these, but they narrow things down.")
        }
    }

    // MARK: - Action bar

    /// Pinned above the keyboard and the tab bar, so the primary action is
    /// never the thing that scrolled off screen.
    private var actionBar: some View {
        VStack(spacing: 8) {
            if !services.networkMonitor.isConnected {
                Label("No internet connection", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !services.configuration.isAIConfigured {
                // Without a provider the button cannot do anything, so the bar
                // offers the step that unblocks it rather than a dead control.
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Add an API key to diagnose", systemImage: "key")
                        .font(.footnote)
                }
            }
            Button(action: startDiagnosis) {
                Text("Diagnose")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canDiagnose || !services.configuration.isAIConfigured)
            .accessibilityHint(diagnoseHint)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var diagnoseHint: String {
        if !services.configuration.isAIConfigured {
            "Add an API key in Settings first"
        } else if model.canDiagnose {
            "Diagnoses the problem you described"
        } else {
            "Add a device and describe the problem first"
        }
    }

    private func startDiagnosis() {
        focusedField = nil
        activeSession = SessionViewModel(
            request: model.request(),
            services: services,
            library: library
        )
        // The problem is saved with the session, so clearing it leaves a clean
        // form for the next one. The device stays: people fix the same things
        // more than once.
        model.clearProblem()
    }
}

#Preview {
    DiagnoseView()
        .environment(PreviewSupport.services)
        .environment(PreviewSupport.library)
        .environment(AppRouter.shared)
        .modelContainer(PreviewSupport.container)
}
