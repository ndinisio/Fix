import Foundation
import Observation

/// The few preferences worth having.
///
/// Deliberately short: a setting that does not change anything the user cares
/// about is clutter in a screen they visit to find one thing.
@MainActor
@Observable
final class AppSettings {
    /// Video search runs on every diagnosis by default. Turning it off saves a
    /// request per diagnosis and keeps the search terms on the device.
    var includeVideos: Bool {
        didSet { defaults.set(includeVideos, forKey: Key.includeVideos) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let includeVideos = "settings.includeVideos"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.includeVideos = defaults.object(forKey: Key.includeVideos) as? Bool ?? true
    }
}
