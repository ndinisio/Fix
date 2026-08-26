import SwiftData
import SwiftUI

@main
struct FIXApp: App {
    @State private var services = ServiceContainer()
    @State private var router = AppRouter.shared
    @State private var library: Library
    private let modelContainer: ModelContainer

    init() {
        let store = Self.makeStore()
        self.modelContainer = store.container
        _library = State(
            initialValue: Library(context: store.container.mainContext, isEphemeral: store.isEphemeral)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(library)
                .environment(router)
        }
        .modelContainer(modelContainer)
    }

    /// Opens the on-disk store, falling back to memory if it cannot be read.
    ///
    /// A damaged store is not a reason to refuse to launch: the app still works,
    /// and Settings says plainly that nothing will be kept.
    private static func makeStore() -> (container: ModelContainer, isEphemeral: Bool) {
        let schema = Schema([SavedDevice.self, StoredSession.self])
        if let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema)
        ) {
            return (container, false)
        }
        guard let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ) else {
            // An in-memory container can only fail if the schema itself is
            // invalid, which is a build-time mistake rather than a runtime one.
            fatalError("FIX could not create its data store.")
        }
        return (container, true)
    }
}
