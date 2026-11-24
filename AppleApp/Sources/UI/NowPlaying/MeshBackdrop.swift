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

/// Upstream `MeshGradientBackground`: four luminous radial blobs sampled from
/// the sleeve, blurred into a wash. Not SwiftUI `MeshGradient` — that warps a
/// vertex grid and is what tore the artwork's edges. Blobs drift once on a
/// track change, then rest.
struct MeshBackdrop: View {
    var seed: Int
    var artwork: Data? = nil
    var initialBase: Color = .black

    private struct PaletteInput: Equatable {
        let seed: Int
        let artwork: Data?
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("musicsk_player_background") private var backgroundMode = "original"
    @AppStorage("ambient_animation") private var animationEnabled = true
    @AppStorage("ambient_transitions") private var transitionsEnabled = true
    @AppStorage("ambient_speed") private var motionSpeed = 1.0
    @AppStorage("ambient_blur") private var blurAmount = 64.0
    @AppStorage("ambient_intensity") private var gradientIntensity = 1.0
    @AppStorage("ambient_saturation") private var saturation = 1.0
    @AppStorage("ambient_brightness") private var brightness = 0.0
    @AppStorage("ambient_darkening") private var darkening = 0.0
    @State private var appliedSeed: Int?
    @State private var phase: Double = 0
    @State private var base: Color?
    @State private var blob0 = Color.clear
    @State private var blob1 = Color.clear
    @State private var blob2 = Color.clear
    @State private var blob3 = Color.clear

    private var reduceBlur: Bool {
        reduceTransparency || PlatformSettings.shared.getBoolean(key: "reduce_dynamic_blur", default: false)
    }
    private var reduceAnimation: Bool {
        reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled ||
            PlatformSettings.shared.getBoolean(key: "reduce_animation", default: false)
    }

    var body: some View {
        Group {
            if backgroundMode == "black" {
                Color.black.ignoresSafeArea().allowsHitTesting(false)
            } else if backgroundMode == "system" {
                (colorScheme == .dark ? Color.black : Color(white: 0.30))
                    .ignoresSafeArea().allowsHitTesting(false)
            } else if backgroundMode == "solid" {
                (base ?? initialBase).ignoresSafeArea().allowsHitTesting(false)
            } else if backgroundMode == "static" || (legacyMesh && backgroundMode == "original") || reduceTransparency {
                // v1.5's backdrop behind its switch: one static wash, no
                // animated blobs. The colour still follows the artwork; only
                // the motion is gone.
                (base ?? initialBase)
                    .overlay {
                        LinearGradient(
                            colors: [Color.black.opacity(0.10), Color.black.opacity(0.38)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                if backgroundMode == "dynamic" {
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0,
                                            paused: reduceAnimation || !animationEnabled)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        animatedMesh(at: reduceAnimation || !animationEnabled ? 0 : time * 0.08 * motionSpeed)
                    }
                } else {
                    animatedMesh(at: phase)
                }
            }
        }
        .saturation(saturation)
        .brightness(backgroundMode == "black" ? 0 : brightness)
        .overlay { Color.black.opacity(darkening).allowsHitTesting(false) }
        .task(id: PaletteInput(seed: seed, artwork: artwork)) {
            let input = PaletteInput(seed: seed, artwork: artwork)
            let palette = await Task.detached(priority: .utility) {
                ArtworkPalette.meshBlobs(from: input.artwork, seed: input.seed)
            }.value
            guard !Task.isCancelled else { return }
            let trackChanged = appliedSeed != input.seed
            apply(palette, first: appliedSeed == nil)
            appliedSeed = input.seed
            if trackChanged && !reduceAnimation && !legacyMesh && backgroundMode == "original" {
                withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 8)) {
                    phase += .pi * 0.45
                }
            }
        }
    }

    private var legacyMesh: Bool {
        PlatformSettings.shared.getBoolean(key: "legacy_mesh_gradient", default: false)
    }

    private func animatedMesh(at angle: Double) -> some View {
        let blobs = [blob0, blob1, blob2, blob3]
        return Canvas(rendersAsynchronously: true) { context, size in
            let anchors: [(CGFloat, CGFloat)] = [
                (0.20, 0.25), (0.80, 0.20), (0.75, 0.80), (0.25, 0.75),
            ]
            let speeds: [Double] = [1, -0.7, 0.85, -1.15]
            let radius = max(size.width, size.height) * 0.62
            for i in 0..<4 {
                let color = blobs[i]
                let x = (anchors[i].0 + 0.16 * cos(angle * speeds[i] + Double(i) * 1.7)) * size.width
                let y = (anchors[i].1 + 0.16 * sin(angle * speeds[i] * 0.9 + Double(i) * 2.3)) * size.height
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.85 * gradientIntensity), color.opacity(0)]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [Color.black.opacity(0.10), Color.black.opacity(0.38)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }
        .background(base ?? initialBase)
        .blur(radius: reduceBlur ? 0 : blurAmount)
        .scaleEffect(1.3)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func apply(_ mesh: ArtworkPalette.MeshBlobs, first: Bool) {
        let run = {
            base = mesh.base
            blob0 = mesh.blobs[0]
            blob1 = mesh.blobs[1]
            blob2 = mesh.blobs[2]
            blob3 = mesh.blobs[3]
        }
        withAnimation(reduceAnimation || !transitionsEnabled ? nil : .easeInOut(duration: first ? 0.24 : 1.4), run)
    }
}
