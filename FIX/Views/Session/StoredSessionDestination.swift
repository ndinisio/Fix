import SwiftUI

/// Opens a saved session from anywhere it is linked to.
///
/// Shared by History and by a device's page so both behave identically,
/// including when the stored payload cannot be read.
struct StoredSessionDestination: View {
    let stored: StoredSession

    @Environment(ServiceContainer.self) private var services
    @Environment(Library.self) private var library

    var body: some View {
        if let session = stored.session {
            SessionView(
                model: SessionViewModel(session: session, services: services, library: library)
            )
        } else {
            // Rare, but silently showing an empty screen would be worse than
            // saying what happened.
            ContentUnavailableView {
                Label("Couldn't Open This Session", systemImage: "doc.questionmark")
            } description: {
                Text("The saved details couldn't be read. You can delete it from History.")
            }
        }
    }
}
