import SwiftUI

/// Three things the app does, three tabs. Each keeps its own navigation stack,
/// so switching away and back returns to where you were.
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Diagnose", systemImage: "stethoscope", value: AppRouter.Tab.diagnose) {
                DiagnoseView()
            }
            Tab("Devices", systemImage: "macbook.and.iphone", value: AppRouter.Tab.devices) {
                DevicesView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppRouter.Tab.history) {
                HistoryView()
            }
        }
    }
}
