import Foundation
import Observation

/// Loading state for a device's care guidance.
///
/// The plan itself is stored on the device so it stays available offline; this
/// only tracks the request that produces it.
@MainActor
@Observable
final class DeviceCareViewModel {
    enum State: Equatable {
        case idle
        case loading
        case failed(APIError)
    }

    private(set) var state: State = .idle

    func loadCarePlan(
        for device: SavedDevice,
        services: ServiceContainer,
        library: Library
    ) async {
        guard state != .loading else { return }
        state = .loading
        do {
            let plan = try await services.troubleshooting.carePlan(for: device.name)
            library.store(carePlan: plan, for: device)
            state = .idle
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.underlying(description: "The connection failed. Try again."))
        }
    }
}
