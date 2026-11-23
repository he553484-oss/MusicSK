import Foundation

/// Only accept a provider-issued HTTPS URL from a successful token response.
enum JioSaavnResponse {
    static func searchRows(data: Data) -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let values: [Any]
        if let rows = root as? [Any] {
            values = rows
        } else if let object = root as? [String: Any] {
            values = (object["results"] as? [Any]) ?? (object["data"] as? [Any]) ?? []
        } else {
            return []
        }
        return values.compactMap { $0 as? [String: Any] }.filter { row in
            guard let id = row["id"] as? String, let title = row["title"] as? String else { return false }
            return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func song(in root: [String: Any], id: String) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        if let songs = root["songs"] as? [Any] {
            return songs.compactMap { $0 as? [String: Any] }.first { ($0["id"] as? String) == id }
        }
        guard let song = root[id] as? [String: Any] else { return nil }
        if let returnedID = song["id"] as? String, returnedID != id { return nil }
        return song
    }

    static func streamURL(data: Data, statusCode: Int) -> URL? {
        guard (200..<300).contains(statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !["failure", "failed", "error", "rejected"].contains(
                (object["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
              ),
              let value = object["auth_url"] as? String,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
