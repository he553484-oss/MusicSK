import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum CanvasVideoFileType: String, CaseIterable {
    case mp4, m4v, mov, webm

    static func candidates(pathExtension: String) -> [Self] {
        let ext = pathExtension.lowercased()
        if ext.isEmpty { return allCases }
        guard let expected = Self(rawValue: ext) else { return [] }
        // A video response can identify a different supported container.
        // Prefer the old filename, then look for the MIME-derived filename.
        return [expected] + allCases.filter { $0 != expected }
    }

    /// A signed provider URL can omit its extension. Only cache such a
    /// response when the server identifies a supported movie container.
    init?(mimeType: String?, pathExtension: String) {
        let mime = mimeType?.lowercased() ?? ""
        guard !mime.contains("mpegurl"), !mime.hasPrefix("text/"), !mime.contains("json") else { return nil }
        switch mime {
        case "video/mp4": self = .mp4
        case "video/x-m4v": self = .m4v
        case "video/quicktime": self = .mov
        case "video/webm": self = .webm
        case "", "application/octet-stream":
            guard let known = Self(rawValue: pathExtension.lowercased()) else { return nil }
            self = known
        default: return nil
        }
    }
}

enum NowPlayingArtworkShape: String, CaseIterable, Sendable {
    case square
    case tall

    /// Classify the displayed dimensions, including the file's orientation.
    /// Apple requires the preview and the movie to match the chosen variant.
    init?(size: CGSize) {
        let width = abs(size.width)
        let height = abs(size.height)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        if width == height {
            self = .square
        } else if width * 4 == height * 3 {
            self = .tall
        } else {
            return nil
        }
    }
}

#if os(iOS)
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct NowPlayingArtworkSource: Equatable, Sendable {
    let primary: URL
    let fallback: URL?

    var urls: [URL] {
        if let fallback, fallback != primary { return [primary, fallback] }
        return [primary]
    }
}

/// Both system adapters retain this value within their request closures. The
/// file remains readable even if the in-app Canvas cache evicts the original.
struct NowPlayingClip: Sendable {
    let id: String
    let shape: NowPlayingArtworkShape
    let file: PublishedCanvasFile
    let preview: Data
}

enum NowPlayingArtworkLoader {
    static func prepare(
        _ source: NowPlayingArtworkSource,
        shapes: Set<NowPlayingArtworkShape>,
        allowDownload: Bool
    ) async -> [NowPlayingArtworkShape: NowPlayingClip] {
        var clips: [NowPlayingArtworkShape: NowPlayingClip] = [:]
        for url in source.urls {
            guard !Task.isCancelled, clips.count < shapes.count else { break }
            if let clip = await prepareClip(url, shapes: shapes.subtracting(clips.keys),
                                            allowDownload: allowDownload) {
                clips[clip.shape] = clip
            }
        }
        return clips
    }

    private static func prepareClip(
        _ url: URL,
        shapes: Set<NowPlayingArtworkShape>,
        allowDownload: Bool
    ) async -> NowPlayingClip? {
        // A provider URL for HLS can still play in-app. The system requires
        // a local video file, so it receives static art when no local variant fits.
        guard let file = await CanvasFileCache.shared.acquirePublishedFile(for: url, allowDownload: allowDownload),
              !Task.isCancelled else { return nil }
        let asset = AVURLAsset(url: file.url)
        do {
            guard try await asset.load(.isPlayable),
                  let video = try await asset.loadTracks(withMediaType: .video).first else { return nil }
            let (size, transform, frameRate) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
            guard let shape = NowPlayingArtworkShape(size: size.applying(transform)),
                  shapes.contains(shape), frameRate.isFinite, frameRate <= 60,
                  !Task.isCancelled else { return nil }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let frame = try await withTaskCancellationHandler {
                try await generator.image(at: .zero).image
            } onCancel: {
                generator.cancelAllCGImageGeneration()
            }
            guard !Task.isCancelled else { return nil }
            let preview = NSMutableData()
            guard NowPlayingArtworkShape(size: CGSize(width: frame.width, height: frame.height)) == shape,
                  let encoder = CGImageDestinationCreateWithData(preview, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(encoder, frame, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(encoder) else { return nil }
            // Same rendition retains its identity across replay and album tracks.
            // Include the first frame signature to detect refreshed URLs serving different artwork.
            let frameHash = SHA256.hash(data: preview as Data)
            let id = DiskCache.hashName("\(url.absoluteString)|\(shape.rawValue)|\(frameHash)")
            return NowPlayingClip(id: id, shape: shape, file: file, preview: preview as Data)
        } catch {
            return nil
        }
    }
}

#endif

/// The clip cache can be cleared or evicted independently of a published
/// resource. A hard link holds the underlying bytes without another download.
final class PublishedCanvasFile: Sendable {
    let url: URL

    init(url: URL) { self.url = url }

    deinit {
        let url = url
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
