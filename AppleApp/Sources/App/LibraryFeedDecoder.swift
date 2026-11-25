import Foundation

/// Validate the authenticated library boundary before giving identities to SwiftUI.
/// The bridge returns account data as JSON; no payload or credentials are logged.
enum LibraryFeedDecoder {
    static func belongsToCurrentSession(_ generation: Int64?, current: Int64) -> Bool {
        generation == current
    }
    struct Item: Equatable {
        let title: String
        let subtitle: String?
        let thumbnailURL: String?
        let videoID: String?
        let browseID: String?
    }
    struct Shelf: Equatable {
        let title: String
        let subtitle: String?
        var items: [Item]
    }

    static func decode(_ data: Data) throws -> [Shelf] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["shelves"] as? [Any] else {
            throw URLError(.cannotDecodeContentData)
        }
        var result: [Shelf] = []
        var shelfIndex: [String: Int] = [:]
        var itemIDs: [String: Set<String>] = [:]
        for case let row as [String: Any] in rows {
            guard let title = nonempty(row["title"]), let items = row["items"] as? [Any] else { continue }
            var valid: [Item] = []
            var seen = itemIDs[title, default: []]
            for case let raw as [String: Any] in items {
                guard let name = nonempty(raw["title"]) else { continue }
                let browse = nonempty(raw["browseId"])
                let video = nonempty(raw["videoId"])
                guard let id = video ?? browse, seen.insert(id).inserted else { continue }
                valid.append(Item(title: name, subtitle: raw["subtitle"] as? String,
                                  thumbnailURL: raw["thumbnailUrl"] as? String,
                                  videoID: video, browseID: browse))
            }
            itemIDs[title] = seen
            guard !valid.isEmpty else { continue }
            if let index = shelfIndex[title] {
                result[index].items.append(contentsOf: valid)
            } else {
                shelfIndex[title] = result.count
                result.append(Shelf(title: title, subtitle: row["subtitle"] as? String, items: valid))
            }
        }
        return result
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
