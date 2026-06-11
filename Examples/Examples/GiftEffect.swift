//
//  GiftEffect.swift
//  Examples
//
//  Created by Sondra on 2026/6/11.
//

import Foundation

struct GiftEffect: Decodable, Equatable {
    let name: String
    let url: URL

    var sourceLabel: String {
        guard let host = url.host?.lowercased() else { return "unknown" }
        if host.contains("qiniu") { return "qiniu" }
        if host.contains("ymres") { return "ymres" }
        if host.contains("res.") { return "res" }
        return host
    }
}

enum GiftEffectsDataSource {
    static func load(from bundle: Bundle = .main) throws -> [GiftEffect] {
        guard let url = bundle.url(forResource: "gift_effects_svga", withExtension: "json") else {
            throw GiftEffectsDataSourceError.missingResource
        }

        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [GiftEffect] {
        try JSONDecoder().decode([GiftEffect].self, from: data)
    }

    static func filter(_ effects: [GiftEffect], query: String) -> [GiftEffect] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return effects }

        return effects.filter { effect in
            effect.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            effect.sourceLabel.localizedCaseInsensitiveContains(trimmedQuery) ||
            (effect.url.host?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }
}

enum GiftEffectsDataSourceError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "gift_effects_svga.json was not found in the app bundle."
        }
    }
}

enum DownloadProgressFormatter {
    static func percentText(for progress: Double) -> String {
        let boundedProgress = min(1, max(0, progress))
        let percentage = Int((boundedProgress * 100).rounded())
        return "\(percentage)%"
    }
}
