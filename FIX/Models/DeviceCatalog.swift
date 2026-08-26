import Foundation

/// The broad kind of thing being fixed. Used only to pick a symbol for a
/// suggestion row — never shown as a label on its own, and never sent to the
/// model, which infers far more from the device name than this could carry.
enum DeviceFamily: String, Codable, Hashable, Sendable {
    case phone, tablet, laptop, desktop, watch, audio, console, tv, printer
    case printer3D, router, camera, appliance, other

    var symbolName: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .watch: "applewatch"
        case .audio: "headphones"
        case .console: "gamecontroller"
        case .tv: "tv"
        case .printer: "printer"
        case .printer3D: "cube"
        case .router: "wifi.router"
        case .camera: "camera"
        case .appliance: "washer"
        case .other: "shippingbox"
        }
    }
}

struct DeviceSuggestion: Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var family: DeviceFamily
}

/// A small, hand-kept list of devices people actually bring to a repair app.
///
/// This is deliberately not a device database. Free text is the input; the
/// catalog only exists to save typing and to give the field a sensible set of
/// suggestions before the user has any history. Anything not listed still
/// works — it is typed, not chosen.
enum DeviceCatalog {
    static let common: [DeviceSuggestion] = [
        .init(name: "iPhone", family: .phone),
        .init(name: "iPad", family: .tablet),
        .init(name: "MacBook Air", family: .laptop),
        .init(name: "MacBook Pro", family: .laptop),
        .init(name: "iMac", family: .desktop),
        .init(name: "Mac mini", family: .desktop),
        .init(name: "Apple Watch", family: .watch),
        .init(name: "AirPods Pro", family: .audio),
        .init(name: "AirPods Max", family: .audio),
        .init(name: "Apple TV", family: .tv),
        .init(name: "HomePod", family: .audio),
        .init(name: "Samsung Galaxy S25", family: .phone),
        .init(name: "Google Pixel", family: .phone),
        .init(name: "Windows PC", family: .desktop),
        .init(name: "Windows laptop", family: .laptop),
        .init(name: "Dell XPS", family: .laptop),
        .init(name: "Surface Pro", family: .tablet),
        .init(name: "PlayStation 5", family: .console),
        .init(name: "Xbox Series X", family: .console),
        .init(name: "Nintendo Switch", family: .console),
        .init(name: "Steam Deck", family: .console),
        .init(name: "Bambu Lab A1", family: .printer3D),
        .init(name: "Prusa MK4", family: .printer3D),
        .init(name: "HP printer", family: .printer),
        .init(name: "Epson printer", family: .printer),
        .init(name: "Brother printer", family: .printer),
        .init(name: "Wi-Fi router", family: .router),
        .init(name: "Sonos speaker", family: .audio),
        .init(name: "Bose headphones", family: .audio),
        .init(name: "Samsung TV", family: .tv),
        .init(name: "LG TV", family: .tv),
        .init(name: "GoPro", family: .camera),
        .init(name: "Sony camera", family: .camera),
        .init(name: "Dyson vacuum", family: .appliance),
        .init(name: "Espresso machine", family: .appliance),
        .init(name: "Washing machine", family: .appliance)
    ]

    /// Keyword lookup for devices the user typed themselves, so a saved device
    /// still gets a sensible symbol.
    private static let familyKeywords: [(keyword: String, family: DeviceFamily)] = [
        ("iphone", .phone), ("galaxy", .phone), ("pixel", .phone), ("phone", .phone),
        ("ipad", .tablet), ("tablet", .tablet), ("surface", .tablet),
        ("macbook", .laptop), ("laptop", .laptop), ("thinkpad", .laptop), ("xps", .laptop),
        ("imac", .desktop), ("mac mini", .desktop), ("mac studio", .desktop),
        ("desktop", .desktop), ("pc", .desktop),
        ("watch", .watch),
        ("airpods", .audio), ("headphone", .audio), ("earbud", .audio), ("speaker", .audio),
        ("homepod", .audio), ("sonos", .audio), ("soundbar", .audio),
        ("playstation", .console), ("ps5", .console), ("ps4", .console), ("xbox", .console),
        ("switch", .console), ("steam deck", .console), ("console", .console),
        ("apple tv", .tv), ("tv", .tv),
        ("bambu", .printer3D), ("prusa", .printer3D), ("ender", .printer3D), ("3d printer", .printer3D),
        ("printer", .printer),
        ("router", .router), ("mesh", .router), ("modem", .router),
        ("camera", .camera), ("gopro", .camera),
        ("vacuum", .appliance), ("washer", .appliance), ("washing", .appliance),
        ("dishwasher", .appliance), ("fridge", .appliance), ("espresso", .appliance),
        ("coffee", .appliance)
    ]

    static func family(for deviceName: String) -> DeviceFamily {
        let name = deviceName.lowercased()
        // Longest keyword first so "apple tv" beats "tv" and "3d printer"
        // beats "printer".
        let match = familyKeywords
            .filter { name.contains($0.keyword) }
            .max { $0.keyword.count < $1.keyword.count }
        return match?.family ?? .other
    }

    /// Suggestions for the device field.
    ///
    /// Recently used devices come first — the strongest signal available — then
    /// catalog entries that start with what was typed, then entries that merely
    /// contain it. An empty query returns recents followed by a short starter
    /// list, so the field is useful before anything has been typed.
    static func suggestions(
        matching query: String,
        recents: [String] = [],
        limit: Int = 6
    ) -> [DeviceSuggestion] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let recentSuggestions = recents.map { DeviceSuggestion(name: $0, family: family(for: $0)) }

        guard !needle.isEmpty else {
            return Array(dedupe(recentSuggestions + common).prefix(limit))
        }

        let pool = dedupe(recentSuggestions + common)
        let prefixed = pool.filter { $0.name.lowercased().hasPrefix(needle) }
        let contained = pool.filter {
            let name = $0.name.lowercased()
            return !name.hasPrefix(needle) && name.contains(needle)
        }
        // An exact match adds nothing: the user has already typed it.
        let matches = (prefixed + contained).filter { $0.name.lowercased() != needle }
        return Array(matches.prefix(limit))
    }

    private static func dedupe(_ suggestions: [DeviceSuggestion]) -> [DeviceSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { seen.insert($0.name.lowercased()).inserted }
    }
}
