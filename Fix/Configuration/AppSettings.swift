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

    /// The model chosen in Settings, overriding the build's default. Not a
    /// secret, so it lives in preferences rather than the Keychain.
    var groqModel: String? {
        didSet { defaults.set(groqModel, forKey: Key.groqModel) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let includeVideos = "settings.includeVideos"
        static let groqModel = "settings.groqModel"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.includeVideos = defaults.object(forKey: Key.includeVideos) as? Bool ?? true
        self.groqModel = defaults.string(forKey: Key.groqModel)?.nilIfBlank
    }
}
