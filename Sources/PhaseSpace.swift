import SwiftUI

struct SpacePoint {
    var x: Double
    var y: Double
    var z: Double
}
func pitchColour(_ midi: Int) -> Color {
    Color(hue: (Double(midi) * 0.61803398875).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 1)
}
enum PhaseSpace {
    // The reference phase controls turns around the ring; the note phase controls its ripples/depth.
    static func orbit(note: Int, root: Int, fraction: Double, fitted: Bool) -> SpacePoint {
        if note == root {
            return SpacePoint(x: 0.64 * cos(2 * .pi * fraction), y: 0.64 * sin(2 * .pi * fraction), z: 0)
        }
        let interval = Harmony.interval(from: root, to: note)
        let referencePhase = 2 * .pi * Double(interval.denominator) * fraction
        let noteCycles = fitted ? Double(interval.numerator) : Double(interval.denominator) * frequencyRatio(note, root)
        let notePhase = 2 * .pi * noteCycles * fraction
        let radius = 0.96 + 0.23 * cos(notePhase)
        return SpacePoint(x: radius * cos(referencePhase), y: radius * sin(referencePhase), z: 0.32 * sin(notePhase))
    }
    private static func frequencyRatio(_ note: Int, _ root: Int) -> Double { pow(2, Double(note - root) / 12) }

    static func point(notes: [Int], time: Double) -> SpacePoint {
        let values = notes.map { sin(2 * .pi * Harmony.frequency($0) * time) }
        if values.count == 1 { return SpacePoint(x: values[0], y: cos(2 * .pi * Harmony.frequency(notes[0]) * time), z: 0) }
        if values.count <= 3 { return SpacePoint(x: values.first ?? 0, y: values.count > 1 ? values[1] : 0, z: values.count > 2 ? values[2] : 0) }
        // Deterministic directions project every selected note into the same 3D space.
        var result = SpacePoint(x: 0, y: 0, z: 0)
        for (index, value) in values.enumerated() {
            let azimuth = Double(index) * 2.399963229728653
            let z = 1 - 2 * (Double(index) + 0.5) / Double(values.count)
            let radius = sqrt(1 - z * z)
            result.x += value * radius * cos(azimuth)
            result.y += value * radius * sin(azimuth)
            result.z += value * z
        }
        let scale = 2 / Double(values.count)
        return SpacePoint(x: result.x * scale, y: result.y * scale, z: result.z * scale)
    }
    static func project(_ point: SpacePoint, yaw: Double, pitch: Double, size: CGSize) -> CGPoint {
        let x = point.x * cos(yaw) + point.z * sin(yaw)
        let z = -point.x * sin(yaw) + point.z * cos(yaw)
        let y = point.y * cos(pitch) - z * sin(pitch)
        let depth = point.y * sin(pitch) + z * cos(pitch)
        let scale = min(size.width, size.height) * 0.29 * 4 / (4 + depth)
        return CGPoint(x: size.width / 2 + x * scale, y: size.height / 2 - y * scale)
    }
}
final class SpaceCamera: ObservableObject {
    @Published var yaw = 0.55
    @Published var pitch = 0.3
    @Published var cycles = 8.0
    @Published var ratioLens = true
    @Published var focused: Int? = nil
    private var dragStart: (Double, Double)?
    func drag(_ translation: CGSize) {
        if dragStart == nil { dragStart = (yaw, pitch) }
        yaw = dragStart!.0 + translation.width * 0.008
        pitch = max(-1.4, min(1.4, dragStart!.1 + translation.height * 0.008))
    }
    func endDrag() { dragStart = nil }
    func reset() { yaw = 0.55; pitch = 0.3; cycles = 8; focused = nil; dragStart = nil }
}
struct PhaseSpaceView: View {
    let notes: [Pitch]
    @ObservedObject var motion: WaveMotion
    @StateObject private var camera = SpaceCamera()
    private var midis: [Int] { notes.map(\.midi).sorted() }
    private func projected(_ point: SpacePoint, size: CGSize) -> CGPoint {
        PhaseSpace.project(point, yaw: camera.yaw, pitch: camera.pitch, size: size)
    }
    private func trajectory(note: Int, from start: Double, to end: Double, size: CGSize, samples: Int) -> Path {
        Path { path in
            for index in 0...samples {
                let fraction = start + (end - start) * Double(index) / Double(samples)
                let point = projected(PhaseSpace.orbit(note: note, root: midis.first ?? note, fraction: fraction, fitted: camera.ratioLens), size: size)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
    private func draw(context: inout GraphicsContext, size: CGSize, date: Date) {
        guard let root = midis.first else { return }
        let rootFrequency = Harmony.frequency(root)
        for midi in midis {
            let interval = Harmony.interval(from: root, to: midi)
            let colour = pitchColour(midi)
            let focused = camera.focused == nil || camera.focused == midi
            let sampleCount = min(16000, max(1000, interval.numerator * 55))
            let path = trajectory(note: midi, from: 0, to: 1, size: size, samples: sampleCount)
            context.stroke(path, with: .color(colour.opacity(focused ? 0.18 : 0.02)), lineWidth: 6)
            context.stroke(path, with: .color(colour.opacity(focused ? 0.85 : 0.12)), lineWidth: midi == root ? 2.5 : 1.8)
            let duration = Double(interval.denominator) / rootFrequency
            let fraction = motion.time(at: date).truncatingRemainder(dividingBy: duration) / duration
            let tail = trajectory(note: midi, from: max(0, fraction - 0.08), to: fraction, size: size, samples: 300)
            context.stroke(tail, with: .color(colour.opacity(focused ? 1 : 0.15)), lineWidth: 3)
            let point = PhaseSpace.orbit(note: midi, root: root, fraction: fraction, fitted: camera.ratioLens)
            let head = projected(point, size: size)
            context.fill(Path(ellipseIn: CGRect(x: head.x - 8, y: head.y - 8, width: 16, height: 16)), with: .color(colour.opacity(focused ? 0.22 : 0.03)))
            context.fill(Path(ellipseIn: CGRect(x: head.x - 3.5, y: head.y - 3.5, width: 7, height: 7)), with: .color(colour.opacity(focused ? 1 : 0.2)))
        }
    }
    private func noteLegend(_ midi: Int) -> some View {
        let root = midis.first ?? midi
        let interval = Harmony.interval(from: root, to: midi)
        return Button {
            camera.focused = camera.focused == midi ? nil : midi
        } label: {
            HStack(spacing: 8) {
                Circle().fill(pitchColour(midi)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(noteName(midi)).font(.system(size: 13, weight: .bold)).foregroundStyle(pitchColour(midi))
                    Text(midi == root ? "Reference ring" : "\(interval.name) · ≈ \(interval.ratio)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if midi != root {
                        Text("\(interval.denominator) turns · \(interval.numerator) ripples")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(pitchColour(midi).opacity(camera.focused == midi ? 0.15 : 0.04), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help("Click to emphasize this note’s orbit; click again to show all")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chordName(notes)).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(mint)
                Spacer()
                Button("Reset view") { camera.reset() }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165))], spacing: 8) {
                ForEach(midis, id: \.self) { midi in noteLegend(midi) }
            }
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: notes.isEmpty)) { timeline in
                Canvas { context, size in draw(context: &context, size: size, date: timeline.date) }
            }.frame(height: 390)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { camera.drag($0.translation) }.onEnded { _ in camera.endDrag() })
                .accessibilityLabel("Coloured, rotatable note orbits showing frequency ratios to the lowest note")
            Text("Each colour is one note. The lowest note is the inner ring; each other orbit shows its relationship to that reference. Drag to rotate; click a note above to emphasize it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("Simple-ratio lens · closed patterns", isOn: $camera.ratioLens).toggleStyle(.checkbox)
                .font(.system(size: 12, weight: .medium))
            Text(camera.ratioLens ? "Illustrated ratios: a fifth uses 2 turns / 3 ripples; a minor third 5 / 6; a semitone 15 / 16. Larger counts create more intricate paths. Sound remains equal-tempered." : "Actual equal-tempered ratios: the same time spans can leave small gaps at the ends. The turn/ripple counts above describe the nearby simple ratios.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            HStack {
                Text("Visualization speed")
                Slider(value: Binding(get: { motion.sliderPosition }, set: { motion.sliderPosition = $0 }), in: -3...0).tint(mint)
                Text(motion.speedLabel).monospacedDigit().frame(width: 100, alignment: .trailing)
            }.font(.system(size: 11))
            Text("Try C5 + G5 (3:2), C5 + E♭5 (6:5), then C5 + C♯5 (16:15). The geometry makes simple versus complex ratios visible; it is not a musical good/bad score.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
