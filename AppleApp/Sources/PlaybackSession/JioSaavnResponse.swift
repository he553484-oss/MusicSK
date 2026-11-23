import Foundation

/// Only accept a provider-issued HTTPS URL from a successful token response.
enum JioSaavnResponse {
    static func song(in root: [String: Any], id: String) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        if let songs = root["songs"] as? [[String: Any]] {
            return songs.first { ($0["id"] as? String) == id }
        }
        guard let song = root[id] as? [String: Any] else { return nil }
        if let returnedID = song["id"] as? String, returnedID != id { return nil }
        return song
    }

    static func streamURL(data: Data, statusCode: Int) -> URL? {
        guard (200..<300).contains(statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["auth_url"] as? String,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
