import SwiftUI

/// What leaves the device, and what does not.
///
/// Written as plain statements about this app's actual behaviour rather than as
/// a policy document. If the app changes, this changes with it.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("FIX has no account and no sign-in. Nothing you type is tied to you.")
            }

            Section("Stays on this device") {
                Label("Your history of diagnoses", systemImage: "iphone")
                Label("Your saved devices and their care guidance", systemImage: "iphone")
            }
            .labelStyle(.titleAndIcon)

            Section {
                Label("The device name you typed", systemImage: "arrow.up.forward")
                Label("The problem you described, and any details you added", systemImage: "arrow.up.forward")
                Label("Which suggested steps didn't work, when you continue", systemImage: "arrow.up.forward")
            } header: {
                Text("Sent when you diagnose")
            } footer: {
                Text("Only this. No identifiers, no contacts, no location, and nothing about the device you're holding.")
            }
            .labelStyle(.titleAndIcon)

            Section {
                Text("Video results come from a search using terms generated for your problem — not the text you wrote.")
            } header: {
                Text("Video search")
            } footer: {
                Text("You can turn videos off in Settings. Videos open outside FIX, in YouTube or Safari.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
}
