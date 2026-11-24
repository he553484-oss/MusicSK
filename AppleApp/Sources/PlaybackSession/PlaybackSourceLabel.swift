import Foundation

/// The queue identifies a recording; the resolved origin identifies the stream actually used.
enum PlaybackSourceLabel {
    static func requested(source: String, id: String, isLocal: Bool) -> String? {
        if source.hasPrefix("saavn:") || id.hasPrefix("saavn:") { return "JioSaavn" }
        if source.hasPrefix("yt:") { return "YouTube" }
        if source.hasPrefix("src:") || id.hasPrefix("src:") { return "Add-on" }
        if isLocal {
            return source.hasPrefix("https://") || source.hasPrefix("http://") ? "Network library" : "Local files"
        }
        return nil
    }

    static func name(origin: String?, source: String, isLocal: Bool) -> String? {
        switch origin {
        case "substitute": return "Alternative source"
        case "youtube": return "YouTube"
        case "jiosaavn": return "JioSaavn"
        case "cache": return "Cached audio"
        case "local": return "Local files"
        default:
            if isLocal { return "Local files" }
            if source.hasPrefix("yt:") { return "YouTube" }
            if source.hasPrefix("src:") { return "Add-on" }
            return nil
        }
    }
}

