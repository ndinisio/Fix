import SwiftData
import SwiftUI

/// Devices the user looks after.
///
/// Saving a device does two things: it removes typing from the next diagnosis,
/// and it gives care guidance somewhere to live.
struct DevicesView: View {
    @Environment(Library.self) private var library

    @Query(sort: \SavedDevice.lastUsedAt, order: .reverse)
    private var devices: [SavedDevice]

    @State private var isAddingDevice = false

    var body: some View {
        NavigationStack {
            Group {
                if devices.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Devices", systemImage: "macbook.and.iphone")
                    } description: {
                        Text("Save the things you own to skip typing them, and to keep their care guidance together.")
                    } actions: {
                        Button("Add Device") { isAddingDevice = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(devices) { device in
                            NavigationLink(value: device) {
                                Label(device.name, systemImage: device.family.symbolName)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                library.delete(devices[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                if !devices.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingDevice = true
                        } label: {
                            Label("Add Device", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingDevice) {
                AddDeviceView()
            }
            .navigationDestination(for: SavedDevice.self) { device in
                DeviceDetailView(device: device)
            }
            .navigationDestination(for: StoredSession.self) { stored in
                StoredSessionDestination(stored: stored)
            }
        }
    }
}

/// Adding a device is one field and two buttons, so it is a sheet at a small
/// detent rather than a pushed screen.
struct AddDeviceView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("iPhone 15, PS5, Bambu Lab A1…", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(save)
                        .accessibilityLabel("Device name")

                    ForEach(DeviceCatalog.suggestions(matching: name)) { suggestion in
                        DeviceSuggestionRow(suggestion: suggestion) {
                            name = suggestion.name
                        }
                    }
                } header: {
                    Text("Device")
                } footer: {
                    Text("Include the model if you know it — advice is more specific with it.")
                }
            }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.nilIfBlank == nil)
                }
            }
            .task { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard name.nilIfBlank != nil else { return }
        library.addDevice(named: name)
        dismiss()
    }
}

#Preview {
    DevicesView()
        .environment(PreviewSupport.library)
        .modelContainer(PreviewSupport.container)
}
