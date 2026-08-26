import Foundation

/// The kind of problem Fix believes it is looking at.
///
/// The category is inferred by the model, never chosen by the user — asking
/// someone to classify a problem they do not understand yet is the wrong way
/// round. It exists to label the diagnosis and to group history.
enum ProblemCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case power
    case battery
    case charging
    case display
    case audio
    case connectivity
    case wifi
    case bluetooth
    case software
    case performance
    case storage
    case overheating
    case account
    case accessories
    case hardware
    case mechanical
    case printing
    case other

    var title: String {
        switch self {
        case .power: "Power"
        case .battery: "Battery"
        case .charging: "Charging"
        case .display: "Display"
        case .audio: "Audio"
        case .connectivity: "Connectivity"
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .software: "Software"
        case .performance: "Performance"
        case .storage: "Storage"
        case .overheating: "Overheating"
        case .account: "Account"
        case .accessories: "Accessories"
        case .hardware: "Hardware"
        case .mechanical: "Mechanical"
        case .printing: "Printing"
        case .other: "Other"
        }
    }

    /// SF Symbol representing the category. Paired with the title everywhere it
    /// appears, so the symbol never has to carry meaning on its own.
    var symbolName: String {
        switch self {
        case .power: "power"
        case .battery: "battery.50percent"
        case .charging: "bolt"
        case .display: "display"
        case .audio: "speaker.wave.2"
        case .connectivity: "antenna.radiowaves.left.and.right"
        case .wifi: "wifi"
        case .bluetooth: "wave.3.right"
        case .software: "app.badge"
        case .performance: "speedometer"
        case .storage: "internaldrive"
        case .overheating: "thermometer.medium"
        case .account: "person.crop.circle"
        case .accessories: "cable.connector"
        case .hardware: "cpu"
        case .mechanical: "gearshape.2"
        case .printing: "printer"
        case .other: "questionmark.circle"
        }
    }

    /// Unknown values decode to ``other`` rather than failing the response: a
    /// category Fix does not recognise is not a reason to lose a diagnosis.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProblemCategory(rawValue: raw.lowercased()) ?? .other
    }
}
