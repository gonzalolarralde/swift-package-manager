import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case overview
        case settings
    }

    enum Sheet: String, Identifiable {
        case about

        var id: String { rawValue }
    }

    var selectedTab: Tab = .overview
    var presentedSheet: Sheet?
    var notificationsEnabled = true
    private(set) var sample: SampleContent = .placeholder

    init() {
        sample = (try? Self.loadSampleContent()) ?? .placeholder
    }

    private static func loadSampleContent() throws -> SampleContent {
        let url = Bundle.module.url(forResource: "SampleContent", withExtension: "json")!
        return try JSONDecoder().decode(SampleContent.self, from: Data(contentsOf: url))
    }
}

struct SampleContent: Codable, Equatable {
    struct Feature: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
    }

    let headline: String
    let summary: String
    let features: [Feature]

    static let placeholder = SampleContent(
        headline: "Custom products",
        summary: "This content is loaded from a SwiftPM resource bundle.",
        features: []
    )
}
