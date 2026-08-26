import Foundation
import Observation
import SwiftData

/// Every write to local storage goes through here.
///
/// Views read with `@Query`, which keeps lists live and native, and write
/// through this type so the rules — de-duplicating device names, keeping a
/// session's summary columns in step with its payload — live in one place
/// instead of being repeated in each screen.
@MainActor
@Observable
final class Library {
    /// True when the on-disk store could not be opened and storage is
    /// memory-only for this launch. Surfaced in Settings so the user is never
    /// quietly losing their history.
    let isEphemeral: Bool

    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext, isEphemeral: Bool = false) {
        self.context = context
        self.isEphemeral = isEphemeral
    }

    // MARK: - Sessions

    /// Inserts or updates the stored copy of a session.
    func save(_ session: TroubleshootingSession) {
        let id = session.id
        let descriptor = FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.apply(session)
        } else {
            context.insert(StoredSession(session: session))
        }
        save()
    }

    func delete(_ stored: StoredSession) {
        context.delete(stored)
        save()
    }

    func deleteAllSessions() {
        try? context.delete(model: StoredSession.self)
        save()
    }

    /// Past sessions for one device, newest first — the "what went wrong
    /// before" list on a device's page.
    func sessions(forDevice device: String, limit: Int = 20) -> [StoredSession] {
        var descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.device == device },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Devices

    /// Names of devices used recently, for the suggestions under the device
    /// field.
    func recentDeviceNames(limit: Int = 4) -> [String] {
        var descriptor = FetchDescriptor<SavedDevice>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(\.name)
    }

    func device(named name: String) -> SavedDevice? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Compared case-insensitively in memory: SwiftData predicates cannot
        // express `localizedCaseInsensitiveCompare`, and the list is small.
        let all = (try? context.fetch(FetchDescriptor<SavedDevice>())) ?? []
        return all.first { $0.name.lowercased() == target }
    }

    /// Saves a device, or updates the one already stored under that name.
    @discardableResult
    func addDevice(named name: String) -> SavedDevice? {
        guard let name = name.nilIfBlank else { return nil }
        if let existing = device(named: name) {
            existing.lastUsedAt = .now
            save()
            return existing
        }
        let device = SavedDevice(name: name)
        context.insert(device)
        save()
        return device
    }

    /// Records that a device was used, without saving a new one. Keeping
    /// suggestions fresh should not quietly fill up someone's device list.
    func markDeviceUsed(_ name: String) {
        guard let existing = device(named: name) else { return }
        existing.lastUsedAt = .now
        save()
    }

    func delete(_ device: SavedDevice) {
        context.delete(device)
        save()
    }

    func deleteAllDevices() {
        try? context.delete(model: SavedDevice.self)
        save()
    }

    func store(carePlan: CarePlan, for device: SavedDevice) {
        device.carePlan = carePlan
        save()
    }

    // MARK: - Private

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Nothing here is worth interrupting the user for: the change is
            // still in memory, and the next save will retry it.
            assertionFailure("Failed to save: \(error)")
        }
    }
}
