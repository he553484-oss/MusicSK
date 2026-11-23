#if os(iOS) && targetEnvironment(simulator)
import SwiftUI

struct AudenSimulatorCheck: ViewModifier {
    @Binding var edition: MusicAppearance
    @Binding var audenTab: Int
    @Environment(PlaybackController.self) private var controller

    func body(content: Content) -> some View {
        content.task {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "musicsk_capture_check_edition") {
                PlaybackDebugLog.shared.record("auden fixture restored edition=\(edition.rawValue)")
            }
            if defaults.bool(forKey: "musicsk_capture_switch_edition") {
                await exerciseDuringPlayback()
            }
        }
    }

    @MainActor
    private func exerciseDuringPlayback() async {
        edition = .original
        audenTab = AppModel.Tab.library.rawValue
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let file = folder.appendingPathComponent("auden-fixture.wav")
        let recording = QueueEntry(id: "auden-fixture", title: "Auden Playback Fixture", artist: "Musicsk",
                                   source: file.path, isLocal: true)
        controller.play([recording], context: "Auden UI regression", boundedContext: true)
        for _ in 0..<30 {
            if controller.isPlaying, controller.engine.positionSeconds() > 0.15 { break }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }
        let from = controller.engine.positionSeconds()
        guard controller.isPlaying, from > 0.15 else {
            PlaybackDebugLog.shared.record("auden fixture failed initial audio")
            return
        }
        let generation = controller.playGeneration
        let queue = controller.queue.map(\.id)
        for appearance in [MusicAppearance.auden, .original, .auden] {
            edition = appearance
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard controller.isPlaying, controller.current?.id == recording.id,
                  controller.playGeneration == generation, controller.queue.map(\.id) == queue else {
                PlaybackDebugLog.shared.record("auden fixture failed shared playback")
                return
            }
        }
        let to = controller.engine.positionSeconds()
        guard to > from + 0.3 else {
            PlaybackDebugLog.shared.record("auden fixture failed native playhead")
            return
        }
        PlaybackDebugLog.shared.record("auden fixture PASS shared playback from=\(from) to=\(to) edition=\(edition.rawValue)")
    }
}
#endif
