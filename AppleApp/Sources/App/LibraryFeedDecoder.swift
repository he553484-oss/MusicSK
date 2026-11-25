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
    struct Report {
        let shelves: [Shelf]
        let malformedCount: Int
        let duplicateCount: Int
    }

    static func decode(_ data: Data) throws -> [Shelf] {
        try decodeWithReport(data).shelves
    }

    static func decodeWithReport(_ data: Data) throws -> Report {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["shelves"] as? [Any] else {
            throw URLError(.cannotDecodeContentData)
        }
        var result: [Shelf] = []
        var shelfIndex: [String: Int] = [:]
        var itemIDs: [String: Set<String>] = [:]
        var malformed = 0
        var duplicates = 0
        for element in rows {
            guard let row = element as? [String: Any], let title = nonempty(row["title"]),
                  let items = row["items"] as? [Any] else { malformed += 1; continue }
            var valid: [Item] = []
            var seen = itemIDs[title, default: []]
            for element in items {
                guard let raw = element as? [String: Any], let name = nonempty(raw["title"]) else {
                    malformed += 1; continue
                }
                let browse = nonempty(raw["browseId"])
                let video = nonempty(raw["videoId"])
                guard let id = video ?? browse else { malformed += 1; continue }
                guard seen.insert(id).inserted else { duplicates += 1; continue }
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
        if result.isEmpty && malformed > 0 { throw URLError(.cannotDecodeContentData) }
        return Report(shelves: result, malformedCount: malformed, duplicateCount: duplicates)
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
