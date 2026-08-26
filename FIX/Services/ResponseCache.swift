import Foundation

/// A small, in-memory cache with expiry.
///
/// Memory only, on purpose. Diagnoses the user chooses to keep are already
/// saved to history; writing a second copy of someone's problem descriptions to
/// disk would be storing personal data for no benefit. This exists to stop the
/// app paying for the same request twice in one sitting.
actor ResponseCache<Value: Sendable> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval
    private let limit: Int
    private let now: @Sendable () -> Date

    init(
        ttl: TimeInterval = 30 * 60,
        limit: Int = 30,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.limit = limit
        self.now = now
    }

    func value(forKey key: String) -> Value? {
        guard let entry = entries[key] else { return nil }
        guard now().timeIntervalSince(entry.storedAt) < ttl else {
            entries[key] = nil
            return nil
        }
        return entry.value
    }

    func insert(_ value: Value, forKey key: String) {
        entries[key] = Entry(value: value, storedAt: now())
        guard entries.count > limit else { return }
        // Evict the oldest entries rather than growing without bound.
        let excess = entries.count - limit
        let oldest = entries
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(excess)
            .map(\.key)
        for key in oldest { entries[key] = nil }
    }

    func removeAll() {
        entries.removeAll()
    }
}
