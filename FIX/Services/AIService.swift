import Foundation

/// The intelligence behind FIX, kept behind a protocol so the provider is an
/// implementation detail.
///
/// Nothing above this layer knows which model answered. Swapping Groq for
/// another provider, or putting a relay in front of it, means adding a type
/// here and changing one line in ``ServiceContainer``.
protocol AIService: Sendable {
    /// One round of troubleshooting advice. Pass previous attempts in the
    /// request to continue a session rather than start it over.
    func diagnose(_ request: DiagnosisRequest) async throws -> Diagnosis

    /// Maintenance guidance for a device the user owns — the "keep it working"
    /// half of the app, requested explicitly rather than generated with every
    /// diagnosis.
    func carePlan(for device: String) async throws -> CarePlan
}

/// Advice for keeping a device healthy, rather than fixing something broken.
struct CarePlan: Codable, Hashable, Sendable {
    var device: String
    /// A sentence on what matters most for this kind of device.
    var summary: String
    var tips: [CareTip]
    /// Early symptoms worth acting on before they become failures.
    var signsToWatch: [String]
    var generatedAt: Date

    init(
        device: String,
        summary: String,
        tips: [CareTip] = [],
        signsToWatch: [String] = [],
        generatedAt: Date = .now
    ) {
        self.device = device
        self.summary = summary
        self.tips = tips
        self.signsToWatch = signsToWatch
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case device, summary, tips, signsToWatch, generatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = container.trimmedString(forKey: .summary) ?? ""
        guard !summary.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .summary, in: container,
                debugDescription: "The care plan has no summary."
            )
        }
        self.device = container.trimmedString(forKey: .device) ?? ""
        self.summary = summary
        self.tips = (try? container.decodeIfPresent([CareTip].self, forKey: .tips)) ?? []
        self.signsToWatch = container.stringList(forKey: .signsToWatch)
        self.generatedAt = (try? container.decodeIfPresent(Date.self, forKey: .generatedAt)) ?? .now
    }

    var isActionable: Bool { !tips.isEmpty || !signsToWatch.isEmpty }
}
