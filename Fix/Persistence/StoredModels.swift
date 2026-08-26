import Foundation
import SwiftData

/// A device the user asked Fix to remember.
///
/// Only what the user typed is stored. Fix does not read the real device
/// identity from the system, and a saved device is a name, not an account.
@Model
final class SavedDevice {
    var name: String = ""
    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now
    /// Encoded ``CarePlan``. Stored so care guidance stays readable offline
    /// once it has been generated.
    var carePlanData: Data?

    init(name: String, createdAt: Date = .now, lastUsedAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    var carePlan: CarePlan? {
        get {
            guard let carePlanData else { return nil }
            return try? JSONDecoder.fix.decode(CarePlan.self, from: carePlanData)
        }
        set {
            carePlanData = newValue.flatMap { try? JSONEncoder.fix.encode($0) }
        }
    }

    var family: DeviceFamily { DeviceCatalog.family(for: name) }
}

/// A troubleshooting session as saved to history.
///
/// The columns that history browses on — device, problem, date, whether it was
/// solved — are stored as properties so they can be sorted and searched. The
/// session itself is kept as encoded JSON, which keeps the schema stable as the
/// diagnosis format evolves and means a past answer stays readable offline.
@Model
final class StoredSession {
    @Attribute(.unique) var id: UUID = UUID()
    var device: String = ""
    var problem: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isSolved: Bool = false
    var categoryRawValue: String = ProblemCategory.other.rawValue
    var payload: Data = Data()

    init(session: TroubleshootingSession) {
        self.id = session.id
        apply(session)
    }

    func apply(_ session: TroubleshootingSession) {
        device = session.device
        problem = session.problem
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        isSolved = session.isSolved
        categoryRawValue = session.category.rawValue
        payload = (try? JSONEncoder.fix.encode(session)) ?? Data()
    }

    /// The decoded session, or `nil` if the stored payload cannot be read —
    /// which the interface treats as a damaged entry rather than a crash.
    var session: TroubleshootingSession? {
        try? JSONDecoder.fix.decode(TroubleshootingSession.self, from: payload)
    }

    var category: ProblemCategory {
        ProblemCategory(rawValue: categoryRawValue) ?? .other
    }
}

extension JSONEncoder {
    /// Shared encoder for anything Fix persists, so stored data stays readable
    /// across releases.
    static let fix: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let fix: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
