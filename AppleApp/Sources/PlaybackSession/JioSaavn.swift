import Foundation
import BitChordShared

/// JioSaavn search + stream — same unofficial catalogue API as upstream
/// `JioSaavnService`. Stream URLs are requested from the provider.
enum JioSaavn {
    private static let base = "https://www.jiosaavn.com/api.php"
    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"

    static func search(_ query: String, session: URLSession = .shared) async -> [SearchHitDTO] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "__call", value: "search.getResults"),
            .init(name: "_format", value: "json"),
            .init(name: "_marker", value: "0"),
            .init(name: "api_version", value: "4"),
            .init(name: "ctx", value: "android"),
            .init(name: "q", value: query),
            .init(name: "p", value: "1"),
            .init(name: "n", value: "8"),
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let results = JioSaavnResponse.searchRows(data: data)
        return results.compactMap { raw in
            guard let rawID = raw["id"] as? String, let rawTitle = raw["title"] as? String else { return nil }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let info = raw["more_info"] as? [String: Any]
            let artistNames = ((info?["artistMap"] as? [String: Any])?["primary_artists"] as? [[String: Any]]) ?? []
            let artists = artistNames.compactMap { $0["name"] as? String }.joined(separator: ", ")
            let image: String?
            if let rawImage = raw["image"] as? String {
                image = rawImage
                    .replacingOccurrences(of: "150x150", with: "500x500")
                    .replacingOccurrences(of: "http://", with: "https://")
            } else {
                image = nil
            }
            let seconds = Int(info?["duration"] as? String ?? "") ?? 0
            let dur = seconds > 0 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : nil
            return SearchHitDTO(
                kind: "track",
                videoId: "saavn:\(id)",
                title: title,
                subtitle: artists,
                thumbnailUrl: image,
                durationText: dur,
                albumName: info?["album"] as? String,
                browseId: nil,
                browseType: nil,
                artistId: nil,
                albumId: nil,
                isVideo: false,
                setVideoId: nil
            )
        }
    }

    enum Failure: Error, Equatable {
        case invalidID, network, accessDenied, notFound, server, invalidResponse, noPlayableSource, cancelled

        static func http(_ status: Int) -> Failure {
            switch status {
            case 401, 403: return .accessDenied
            case 404: return .notFound
            case 500...599: return .server
            default: return .invalidResponse
            }
        }
    }

    static func streamURL(for trackId: String, session: URLSession = .shared) async -> (url: String, kbps: Int)? {
        try? await resolveStream(for: trackId, session: session).get()
    }

    static func resolveStream(for trackId: String, session: URLSession = .shared) async -> Result<(url: String, kbps: Int), Failure> {
        let id = (trackId.hasPrefix("saavn:") ? String(trackId.dropFirst(6)) : trackId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return .failure(.invalidID) }
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            .init(name: "__call", value: "song.getDetails"),
            .init(name: "_format", value: "json"),
            .init(name: "_marker", value: "0"),
            .init(name: "api_version", value: "4"),
            .init(name: "ctx", value: "android"),
            .init(name: "pids", value: id),
        ]
        guard let url = comps.url else { return .failure(.invalidID) }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            return .failure(Task.isCancelled ? .cancelled : .network)
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
        guard (200..<300).contains(http.statusCode) else { return .failure(.http(http.statusCode)) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidResponse)
        }
        guard let song = JioSaavnResponse.song(in: root, id: id) else { return .failure(.notFound) }
        guard let info = song["more_info"] as? [String: Any],
              let encrypted = info["encrypted_media_url"] as? String,
              !encrypted.isEmpty else { return .failure(.noPlayableSource) }

        // Ask the service for a playable URL. Rewriting a decrypted URL to
        // pretend that a 320 kbps rendition exists can produce a broken URL.
        var failure: Failure = .noPlayableSource
        for bitrate in [320, 160, 96, 48] {
            guard !Task.isCancelled else { return .failure(.cancelled) }
            var tokenComponents = URLComponents(string: base)!
            tokenComponents.queryItems = [
                .init(name: "__call", value: "song.generateAuthToken"),
                .init(name: "_format", value: "json"),
                .init(name: "_marker", value: "0"),
                .init(name: "api_version", value: "4"),
                .init(name: "ctx", value: "android"),
                .init(name: "url", value: encrypted),
                .init(name: "bitrate", value: String(bitrate)),
            ]
            guard let tokenURL = tokenComponents.url else { continue }
            var tokenRequest = URLRequest(url: tokenURL, timeoutInterval: 12)
            tokenRequest.setValue(ua, forHTTPHeaderField: "User-Agent")
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: tokenRequest)
                guard let http = response as? HTTPURLResponse else { failure = .invalidResponse; continue }
                guard (200..<300).contains(http.statusCode) else {
                    failure = .http(http.statusCode)
                    // An access denial or service failure applies to the request,
                    // not evidence that a lower rendition is authorized.
                    if failure == .accessDenied || failure == .server { return .failure(failure) }
                    continue
                }
                guard let url = JioSaavnResponse.streamURL(data: data, statusCode: http.statusCode) else {
                    failure = .invalidResponse
                    continue
                }
                return .success((url.absoluteString, bitrate))
            } catch {
                if Task.isCancelled { return .failure(.cancelled) }
                return .failure(.network)
            }
        }
        return .failure(failure)
    }

    /// Upstream `matchAndStream` for this catalogue: search, score, then open
    /// the best row that is the same recording. Nil means fall through to YouTube.
    static func matchedStream(
        for entry: QueueEntry, playingDurationSec: Int? = nil
    ) async -> (url: String, kbps: Int, durationSec: Int?)? {
        let target = TrackMatch.Target(
            title: entry.title,
            artist: entry.artist,
            durationSec: playingDurationSec ?? PlaybackDuration.roundedSeconds(entry.durationSeconds)
        )
        if target.title.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        let query = [target.title, target.artist].filter { !$0.isEmpty }.joined(separator: " ")
        let hits = await search(query)
        let candidates = hits.map {
            TrackMatch.Candidate(title: $0.title, artist: $0.subtitle ?? "", durationText: $0.durationText)
        }
        guard let index = TrackMatch.bestIndex(in: candidates, target: target),
              let sid = hits[index].videoId else { return nil }
        guard let stream = await streamURL(for: sid) else { return nil }
        return (stream.url, stream.kbps, TrackMatch.seconds(of: hits[index].durationText))
    }

}
