#if os(iOS)
import AVFAudio
import MediaPlayer
import SwiftUI
import UIKit

struct SystemVolumeRow: View {
    var hugsGlyphs: Bool
    var onEditingChanged: (Bool) -> Void
    @State private var volume = AVAudioSession.sharedInstance().outputVolume

    var body: some View {
        HStack(spacing: 10) {
            speaker(volume == 0 ? "speaker.slash.fill" : "speaker.fill",
                    alignment: hugsGlyphs ? .leading : .center)
            SystemVolumeSlider(onVolumeChanged: { volume = $0 }, onEditingChanged: onEditingChanged)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            speaker("speaker.wave.3.fill", alignment: hugsGlyphs ? .trailing : .center)
        }
    }

    private func speaker(_ symbol: String, alignment: Alignment) -> some View {
        Image(systemName: symbol)
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 16, height: 16, alignment: alignment)
            .playerGlyph()
            .accessibilityHidden(true)
    }
}

/// Keep the native control visible so iOS owns the adjustment, route support,
/// hardware button updates and accessibility.
private struct SystemVolumeSlider: UIViewRepresentable {
    var onVolumeChanged: (Float) -> Void
    var onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVolumeChanged: onVolumeChanged, onEditingChanged: onEditingChanged)
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.showsRouteButton = false
        view.tintColor = .white
        context.coordinator.connect(to: view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.onVolumeChanged = onVolumeChanged
        context.coordinator.onEditingChanged = onEditingChanged
    }

    static func dismantleUIView(_ uiView: MPVolumeView, coordinator: Coordinator) {
        coordinator.disconnect(from: uiView)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onVolumeChanged: (Float) -> Void
        var onEditingChanged: (Bool) -> Void
        private var observation: NSKeyValueObservation?
        private var editing = false
        private lazy var touchObserver = UILongPressGestureRecognizer(
            target: self, action: #selector(editingGestureChanged(_:))
        )

        init(onVolumeChanged: @escaping (Float) -> Void, onEditingChanged: @escaping (Bool) -> Void) {
            self.onVolumeChanged = onVolumeChanged
            self.onEditingChanged = onEditingChanged
        }

        func connect(to view: MPVolumeView) {
            // The observation only updates the adjacent mute glyph.
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.observation != nil else { return }
                    self.onVolumeChanged(AVAudioSession.sharedInstance().outputVolume)
                }
            }
            // Suspend lyric-control auto-hide while a hand rests on the
            // control. The system's slider continues to handle the touch.
            touchObserver.minimumPressDuration = 0
            touchObserver.allowableMovement = .greatestFiniteMagnitude
            touchObserver.cancelsTouchesInView = false
            touchObserver.delaysTouchesBegan = false
            touchObserver.delaysTouchesEnded = false
            touchObserver.delegate = self
            view.addGestureRecognizer(touchObserver)
        }

        func disconnect(from view: MPVolumeView) {
            observation?.invalidate()
            observation = nil
            let wasEditing = editing
            editing = false
            view.removeGestureRecognizer(touchObserver)
            if wasEditing {
                Task { @MainActor [onEditingChanged] in onEditingChanged(false) }
            }
        }

        @objc private func editingGestureChanged(_ gesture: UIGestureRecognizer) {
            let isEditing = gesture.state == .began || gesture.state == .changed
            guard isEditing != editing else { return }
            editing = isEditing
            onEditingChanged(editing)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
