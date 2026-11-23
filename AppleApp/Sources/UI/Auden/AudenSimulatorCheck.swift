#if os(iOS) && targetEnvironment(simulator)
import SwiftUI

struct AudenSimulatorCheck: ViewModifier {
    @Binding var edition: MusicAppearance
    @Binding var audenTab: Int
    @Environment(PlaybackController.self) private var controller
    @Environment(\.scenePhase) private var phase
    @State private var exercised = false

    func body(content: Content) -> some View {
        content.task(id: phase) {
            guard phase == .active, !exercised else { return }
            exercised = true
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "musicsk_capture_check_edition") {
                PlaybackDebugLog.shared.record("auden fixture restored edition=\(edition.rawValue)")
            }
            if defaults.bool(forKey: "musicsk_capture_switch_edition") {
                await exerciseAppearance()
            }
        }
    }

    @MainActor
    private func exerciseAppearance() async {
        edition = .original
        audenTab = AppModel.Tab.library.rawValue
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            PlaybackDebugLog.shared.record("auden fixture FAIL missing Documents directory")
            return
        }
        let file = folder.appendingPathComponent("auden-fixture.wav")
        let recording = QueueEntry(id: "auden-fixture", title: "Auden Playback Fixture", artist: "Musicsk",
                                   source: file.path, durationText: "1:30", isLocal: true)
        controller.play([recording], context: "Auden UI regression", contextID: "auden-fixture", boundedContext: true)
        for _ in 0..<70 {
            if controller.isPlaying, controller.engine.positionSeconds() > 0.15 { break }
            if controller.lastError != nil { break }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }
        let from = controller.engine.positionSeconds()
        let audioStarted = controller.isPlaying && from > 0.15
        if !audioStarted {
            let health = controller.outputHealth
            let output = controller.engine.outputDevice()
            PlaybackDebugLog.shared.record(
                "auden fixture FAIL initial audio file=\(FileManager.default.fileExists(atPath: file.path)) " +
                "state=\(controller.state) active=\(AudioSessionManager.isActive) output_started=\(output.started) " +
                "rate=\(output.sampleRate) position=\(from) peak=\(health.outputPeak) " +
                "error=\(controller.lastError ?? "none")"
            )
        }
        let generation = controller.playGeneration
        let queue = controller.queue.map(\.id)
        var unchanged = true
        for appearance in [MusicAppearance.auden, .original, .auden] {
            edition = appearance
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            unchanged = unchanged && controller.current?.id == recording.id
                && controller.playGeneration == generation && controller.queue.map(\.id) == queue
                && (!audioStarted || controller.isPlaying)
        }
        let to = controller.engine.positionSeconds()
        if audioStarted {
            if unchanged, to > from + 0.3 {
                PlaybackDebugLog.shared.record("auden fixture PASS shared playback from=\(from) to=\(to) edition=\(edition.rawValue)")
            } else {
                PlaybackDebugLog.shared.record("auden fixture FAIL shared playback unchanged=\(unchanged) from=\(from) to=\(to)")
            }
        } else {
            PlaybackDebugLog.shared.record("auden fixture queue unchanged=\(unchanged)")
        }
        PlaybackDebugLog.shared.record("auden fixture switch complete edition=\(edition.rawValue)")
    }
}
#endif
