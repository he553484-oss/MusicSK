import SwiftUI
import BitChordShared
import UniformTypeIdentifiers
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
import AVFAudio
#else
import AppKit
#endif

/// Queue column. The current song stays in the compact player header when
/// there is no neighbouring player column (portrait); wide layouts already have
/// that information beside the queue, so they omit the duplicate header.
struct UpNextPane: View {
    @Environment(PlaybackController.self) private var controller
    @Environment(AuthController.self) private var auth
    @Environment(\.musicAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var showsCurrentTrackHeader = true
    var onOpenLyrics: () -> Void = {}
    @State private var hasScrolledOnce = false
    @AppStorage("show_queue_history") private var showQueueHistory = false

    /// The queue list, one layout on every platform: "Queue" with Clear, a
    /// "Now playing" section for the current track, "Up next" with drag
    /// handles left and remove buttons right, the AutoPlay section, and a
    /// Lyrics link at the foot. iPad and mac used to render a separate
    /// "Continue Playing" list (no sections, swipe-only delete); the two
    /// layouts disagreed about what a queue is, so there is one now.
    @ViewBuilder
    var body: some View {
        queueList
    }

    private var isAuden: Bool {
        #if os(iOS)
        appearance == .auden
        #else
        false
        #endif
    }

    private var gutter: CGFloat { isAuden ? AudenPlayerMetrics.gutter : 24 }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: isAuden ? 4 : 12) {
            // The big current-track header (artwork, like, menu) only where
            // the artwork column is absent. iPad landscape and mac show all
            // of that on the left already; repeating it here doubles the
            // song, the like and the menu.
            if showsCurrentTrackHeader {
                queueHeader
            }
            HStack(alignment: .firstTextBaseline) {
                if !isAuden {
                    Text("Queue").font(.title2.weight(.bold)).foregroundStyle(.white)
                }
                Spacer()
                if !manualUpcoming.isEmpty || !autoplayUpcoming.isEmpty {
                    Button("Clear") { controller.clearUpcoming() }
                        .buttonStyle(.plain)
                        .font(isAuden ? .system(size: 16, weight: .semibold) : .callout.weight(.semibold))
                        .foregroundStyle(isAuden ? Color.white.opacity(0.75) : Color.accentColor)
                }
            }
            .padding(.horizontal, gutter)
            .id("queueTop")
            #if os(iOS)
            if isAuden {
                AudenQueueModes()
                    .padding(.top, 6)
                    .padding(.horizontal, gutter)
            }
            #endif

            if controller.current == nil && manualUpcoming.isEmpty && autoplayUpcoming.isEmpty {
                Text("Nothing playing.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 8)
                    .padding(.horizontal, gutter)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List {
                        if !historyRows.isEmpty {
                            Text("Previously Played")
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.top, isAuden ? 0 : 12)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 12, leading: gutter, bottom: 6, trailing: gutter))
                            ForEach(historyRows) { item in
                                historyQueueRow(item)
                            }
                        }
                        if controller.current != nil {
                            Text("Now playing")
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.top, isAuden ? 0 : 12)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 12, leading: gutter, bottom: 6, trailing: gutter))
                            currentQueueRow
                        }
                        if !manualUpcoming.isEmpty {
                            Text("Up next")
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.top, isAuden ? 0 : 16)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 16, leading: gutter, bottom: 6, trailing: gutter))
                            ForEach(Array(manualUpcoming.enumerated()), id: \.element.id) { localIndex, item in
                                queueListRow(item, section: 0, index: localIndex, rows: manualUpcoming)
                            }
                            .onMove { source, dest in move(source, dest, rows: manualUpcoming) }
                            .onDelete { offsets in remove(offsets, rows: manualUpcoming) }
                        }
                        if controller.autoplayEnabled || !autoplayUpcoming.isEmpty {
                            HStack(spacing: 8) {
                                Image(.bchInfinity)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.white.opacity(0.75))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("AutoPlay")
                                        .font(.headline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text(autoplayUpcoming.isEmpty
                                         ? "Similar music will keep playing"
                                         : "Similar music, selected to play next")
                                        .font(.callout)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            .padding(.vertical, isAuden ? 0 : 14)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 14, leading: gutter, bottom: 14, trailing: gutter))
                            if !autoplayUpcoming.isEmpty {
                                ForEach(Array(autoplayUpcoming.enumerated()), id: \.element.id) { localIndex, item in
                                    queueListRow(item, section: 1, index: localIndex, rows: autoplayUpcoming)
                                }
                                .onMove { source, dest in move(source, dest, rows: autoplayUpcoming) }
                                .onDelete { offsets in remove(offsets, rows: autoplayUpcoming) }
                            }
                        }
                        Button {
                            Haptics.play(.expand)
                            onOpenLyrics()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "music.note")
                                    .font(.body.weight(.medium))
                                Text("Lyrics")
                                    .font(.headline.weight(.medium))
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: gutter, bottom: 10, trailing: gutter))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.04),
                                .init(color: .black, location: 0.96),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .animation(isAuden
                        ? (reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.2))
                        : .easeOut(duration: 0.2), value: queueSignature)
                    .onChange(of: controller.playingIndex) { _, _ in
                        if hasScrolledOnce {
                            withAnimation {
                                proxy.scrollTo(showQueueHistory ? "nowPlaying" : "queueTop", anchor: .top)
                            }
                        } else {
                            proxy.scrollTo(showQueueHistory ? "nowPlaying" : "queueTop", anchor: .top)
                            hasScrolledOnce = true
                        }
                    }
                    .onAppear {
                        guard showQueueHistory else { return }
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo("nowPlaying", anchor: .top)
                            hasScrolledOnce = true
                        }
                    }
                    .onChange(of: showQueueHistory) { _, enabled in
                        guard enabled else { return }
                        withAnimation { proxy.scrollTo("nowPlaying", anchor: .top) }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var currentQueueRow: some View {
        Button {
            let at = controller.playingIndex
            if controller.queue.indices.contains(at) {
                controller.playQueueItem(at: at)
            }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(entry: controller.current, side: isAuden ? 44 : 40)
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.current?.title ?? "")
                        .font(isAuden ? .system(size: 16, weight: .semibold) : .body.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    ArtistCreditText(
                        credit: controller.current?.artist ?? "",
                        artistId: controller.current?.artistId,
                        font: isAuden ? .system(size: 14) : .caption,
                        color: .white.opacity(isAuden ? 0.55 : 0.65)
                    )
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Now playing")
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(isAuden ? EdgeInsets(top: 6, leading: gutter, bottom: 6, trailing: gutter) : nil)
        .id("nowPlaying")
    }

    private var historyRows: [QueueRow] {
        guard showQueueHistory, controller.playingIndex > 0 else { return [] }
        return (0..<min(controller.playingIndex, controller.queue.count)).map { index in
            QueueRow(index: index, entry: controller.queue[index])
        }
    }

    private func historyQueueRow(_ item: QueueRow) -> some View {
        Button {
            controller.playQueueItem(at: item.index)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(entry: item.entry, side: 44)
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.entry.title)
                        .font(isAuden ? .system(size: 16, weight: .semibold) : .body.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.entry.artist)
                        .font(isAuden ? .system(size: 14) : .caption)
                        .foregroundStyle(.white.opacity(isAuden ? 0.55 : 0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(item.entry.title), previously played")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: gutter, bottom: 6, trailing: isAuden ? gutter : 20))
    }

    private func queueListRow(_ item: QueueRow, section: Int, index: Int, rows: [QueueRow]) -> some View {
        HStack(spacing: isAuden ? 4 : 10) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20, height: 44)
                .contentShape(.rect)
                .onDrag { NSItemProvider(object: "\(section):\(index)" as NSString) }
            Button {
                controller.playQueueItem(at: item.index)
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(entry: item.entry, side: 44)
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.entry.title)
                            .font(isAuden ? .system(size: 16, weight: .semibold) : .body.weight(.medium))
                            .foregroundStyle(.white.opacity(isAuden ? 0.92 : 1))
                            .lineLimit(1)
                        Text(item.entry.artist)
                            .font(isAuden ? .system(size: 14) : .caption)
                            .foregroundStyle(.white.opacity(isAuden ? 0.55 : 0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                controller.removeFromQueue(at: item.index)
            } label: {
                Image(systemName: "xmark")
                    .font(isAuden ? .system(size: 18, weight: .medium) : .body.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.entry.title) from queue")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: gutter, bottom: 6, trailing: isAuden ? gutter : 20))
        .onDrop(of: [.text], delegate: QueueReorderDelegate(section: section, rows: rows, destIndex: index) { from, dest in
            move(IndexSet(integer: from), dest, rows: rows)
        })
    }

    private var autoplayStart: Int { controller.autoplaySectionStart }

    /// Upcoming manual rows — never includes AutoPlay, never the playing track.
    private var manualUpcoming: [QueueRow] {
        rows(in: controller.firstMovableQueueIndex..<autoplayStart)
    }

    private var autoplayUpcoming: [QueueRow] {
        rows(in: autoplayStart..<controller.queue.count)
    }

    private func rows(in range: Range<Int>) -> [QueueRow] {
        guard range.lowerBound < range.upperBound else { return [] }
        return range.compactMap { index in
            guard controller.queue.indices.contains(index) else { return nil }
            return QueueRow(index: index, entry: controller.queue[index])
        }
    }

    private var queueHeader: some View {
        HStack(spacing: 12) {
            ArtworkView(entry: controller.current, side: isAuden ? AudenPlayerMetrics.headerArt : 56)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(controller.current?.title ?? "Nothing playing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(controller.current?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if auth.signedIn, controller.current?.videoId != nil {
                GlassCircleButton(
                    icon: controller.isLiked ? .bchHeartFilled : .bchHeart,
                    label: controller.isLiked ? "Remove Like" : "Like"
                ) { controller.toggleLike() }
            }
            Menu {
                if let current = controller.current {
                    SongActionButtons(entry: current, showSleepTimer: true, showDebugLog: true)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help("More")
            .accessibilityLabel("More")
        }
        .padding(.horizontal, gutter)
    }

    /// What the row-motion animation tracks: every move changes it, nothing
    /// else does.
    private var queueSignature: String {
        (manualUpcoming.map(\.id) + autoplayUpcoming.map(\.id)).joined(separator: "|")
    }

    private func move(_ source: IndexSet, _ dest: Int, rows: [QueueRow]) {
        guard let fromLocal = source.first, rows.indices.contains(fromLocal) else { return }
        let fromQueue = rows[fromLocal].index
        let clampedDest = min(max(dest, 0), rows.count)
        let toQueue: Int
        if clampedDest >= rows.count {
            toQueue = (rows.last?.index ?? fromQueue) + 1
        } else {
            toQueue = rows[clampedDest].index
        }
        controller.moveQueue(from: IndexSet(integer: fromQueue), to: toQueue)
    }

    private func remove(_ offsets: IndexSet, rows: [QueueRow]) {
        let indices = IndexSet(offsets.compactMap { rows.indices.contains($0) ? rows[$0].index : nil })
        controller.removeFromQueue(at: indices)
    }
}

/// Reorders within one queue section from the row's drag handle, like
/// upstream: a drag never leaves its section, and neighbours trade slots
/// live as the held row crosses them. The payload carries its section tag so
/// a drop onto the other section's rows is ignored, not misfiled.
private struct QueueReorderDelegate: DropDelegate {
    let section: Int
    let rows: [QueueRow]
    let destIndex: Int
    let onMove: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String else { return }
            let parts = text.split(separator: ":").map(String.init).compactMap(Int.init)
            guard parts.count == 2, parts[0] == section else { return }
            let from = parts[1]
            guard rows.indices.contains(from), rows.indices.contains(destIndex), from != destIndex else { return }
            Task { @MainActor in onMove(from, destIndex) }
        }
    }

    func performDrop(info: DropInfo) -> Bool { true }
}

private struct QueueRow: Identifiable {
    let index: Int
    let entry: QueueEntry
    var id: String { "\(index)-\(entry.id)" }
}
