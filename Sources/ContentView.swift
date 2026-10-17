import SwiftUI

let appBackground = Color(red: 0.045, green: 0.06, blue: 0.095)
let mint = Color(red: 0.36, green: 0.92, blue: 0.77)
final class WaveMotion: ObservableObject {
    private var epoch = Date()
    private var offset = 0.0
    @Published private(set) var speed = 0.004
    func time(at date: Date) -> Double { offset + date.timeIntervalSince(epoch) * speed }
    var sliderPosition: Double {
        get { log10(speed) }
        set {
            let now = Date()
            offset = time(at: now)
            epoch = now
            speed = pow(10, newValue)
        }
    }
    var speedLabel: String { speed >= 0.999 ? "Real time" : "\(Int((1 / speed).rounded()))× slower" }
    @Published var combined = true
    @Published var showMotion = false
}
struct ContentView: View {
    @StateObject var audio = Analyzer()
    @StateObject private var motion = WaveMotion()
    var dominant: Pitch? { audio.notes.max { $0.strength < $1.strength } }
    var gold: Color { Color(red: 1, green: 0.79, blue: 0.32) }
    func prominence(_ note: Pitch) -> Double {
        min(1, Double(note.strength / max(dominant?.strength ?? 1, 0.001)))
    }
    func noteColor(_ note: Pitch) -> Color {
        if !audio.heldNotes.isEmpty {
            return pitchColour(note.midi)
        }
        let weight = pow(prominence(note), 2)
        return Color(red: 0.22 + 0.78 * weight, green: 0.58 + 0.21 * weight, blue: 0.76 - 0.44 * weight)
    }
    func keyFill(_ midi: Int, black: Bool) -> LinearGradient {
        let note = audio.notes.first { $0.midi == midi }
        let base = black ? Color(red: 0.08, green: 0.1, blue: 0.14) : Color(white: 0.89)
        let color = note.map { noteColor($0) } ?? base
        return LinearGradient(colors: [color, color.opacity(note == nil ? 1 : 0.45 + 0.55 * prominence(note!))], startPoint: .trailing, endPoint: .leading)
    }
    var body: some View {
        HStack(spacing: 0) {
            piano
            dashboard
        }.frame(minWidth: 930, minHeight: 720).background(appBackground).preferredColorScheme(.dark)
    }
    func tracePath(_ values: [Float], size: CGSize, spectrum: Bool) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let y = spectrum ? size.height * (1 - Double(value)) : size.height / 2 - Double(value) * size.height * 3.8
                let point = CGPoint(x: size.width * Double(index) / Double(max(1, values.count - 1)), y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
    var frozenPattern: [(midi: Int, cycles: Int)] { Harmony.fittedPattern(audio.notes.map(\.midi)) }
    var frozenSpan: Double {
        Double(frozenPattern.first?.cycles ?? 8) / Harmony.frequency(audio.notes.first?.midi ?? 60)
    }
    func cycleLane(_ note: Pitch) -> some View {
        let fitted = frozenPattern.first { $0.midi == note.midi }
        let cycles = fitted.map { Double($0.cycles) } ?? Harmony.frequency(note.midi) * frozenSpan
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(note.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(noteColor(note))
                Text(fitted == nil ? String(format: "%.2f cycles", cycles) : "\(fitted!.cycles) cycles")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if let root = audio.notes.first, note.midi != root.midi {
                    let interval = Harmony.interval(from: root.midi, to: note.midi)
                    Text("Actual tuning: \(interval.centsFromRatio, specifier: "%+.1f")¢ from ratio")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.frame(width: 145, alignment: .leading)
            GeometryReader { geo in
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height * 0.58))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.58))
                    }.stroke(.white.opacity(0.1), lineWidth: 1)
                    ForEach(0..<min(24, Int(cycles.rounded(.down))), id: \.self) { index in
                        Text("\(index + 1)").font(.system(size: 9, design: .monospaced)).foregroundStyle(noteColor(note).opacity(0.7))
                            .position(x: geo.size.width * (Double(index) + 0.5) / cycles, y: 9)
                    }
                    Path { path in
                        for index in 0..<1000 {
                            let x = Double(index) / 999
                            let point = CGPoint(x: geo.size.width * x, y: geo.size.height * 0.58 - sin(2 * .pi * cycles * x) * geo.size.height * 0.28)
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }.stroke(noteColor(note), lineWidth: 2)
                    HStack { Rectangle().frame(width: 2); Spacer(); Rectangle().frame(width: 2) }
                        .foregroundStyle(frozenPattern.isEmpty ? .white.opacity(0.15) : gold.opacity(0.65))
                }.clipped()
            }.frame(height: 78)
        }.padding(.horizontal, 12).padding(.vertical, 6)
            .background(noteColor(note).opacity(0.04))
    }
    func intervalCard(_ pair: NotePair) -> some View {
        let interval = Harmony.interval(from: pair.lower, to: pair.upper)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(noteName(pair.lower)) – \(noteName(pair.upper))").font(.system(size: 12, weight: .semibold)).foregroundStyle(mint)
            Text("\(interval.name) · ≈ \(interval.ratio)").font(.system(size: 11))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    var frozenHarmony: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(chordName(audio.notes)).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(mint)
            Text(Harmony.chordExplanation(audio.notes.map(\.midi))).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(frozenPattern.isEmpty ? "ACTUAL CYCLES · ONE SHARED TIME SPAN" : "FITTED CYCLE PATTERN · " + frozenPattern.map { String($0.cycles) }.joined(separator: " : "))
                .font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(gold)
            Text(frozenPattern.isEmpty ? "No short fitted pattern for this selection. These waves show the actual equal-tempered cycle counts over eight cycles of the lowest note." : "Read each row from left to right: the numbered cycles fit into the same duration. The gold edges mark the start and end of this idealized ratio pattern.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            VStack(spacing: 1) { ForEach(audio.notes) { note in cycleLane(note) } }
            if !frozenPattern.isEmpty {
                Text("This is a frozen simple-ratio illustration. Audio stays in equal temperament, so most notes differ slightly from the fitted pattern. A neat pattern explains a relationship; it is not a good/bad harmony score.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if audio.notes.count > 1 {
                Text("INTERVALS BETWEEN EVERY PAIR").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Harmony.pairs(audio.notes.map(\.midi))) { pair in intervalCard(pair) }
                    }
                }.frame(height: min(190, Double((Harmony.pairs(audio.notes.map(\.midi)).count + 1) / 2) * 62))
            }
        }
    }
    var harmonySpan: Double { 8 / Harmony.frequency(audio.notes.first?.midi ?? 60) }
    func movingWave(_ midis: [Int], elapsed: Double, size: CGSize) -> Path {
        Path { path in
            for index in 0..<900 {
                let t = elapsed + Double(index) / 899 * harmonySpan
                let point = CGPoint(x: size.width * Double(index) / 899, y: size.height / 2 - Harmony.sample(midis, at: t) * size.height * 0.34)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
    func harmonyLane(_ midis: [Int], elapsed: Double, color: Color) -> some View {
        GeometryReader { geo in
            let guides = Harmony.guides(audio.notes.map(\.midi), start: elapsed, span: harmonySpan)
            let pulse = Harmony.alignmentStrength(audio.notes.map(\.midi), at: elapsed + 0.22 * harmonySpan)
            ZStack {
                repeatShade(guides, size: geo.size)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }.stroke(.white.opacity(0.08), lineWidth: 1)
                Path { path in
                    for guide in guides where !guide.aligned {
                        let x = guide.fraction * geo.size.width
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                }.stroke(.white.opacity(0.025), lineWidth: 1)
                Path { path in
                    for guide in guides where guide.aligned {
                        let x = guide.fraction * geo.size.width
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                }.stroke(gold.opacity(0.18), lineWidth: 1)
                movingWave(midis, elapsed: elapsed, size: geo.size).stroke(color, lineWidth: 2)
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1)
                    .position(x: geo.size.width * 0.22, y: geo.size.height / 2)
                Circle().fill(gold.opacity(pulse * 0.3)).frame(width: 16 + pulse * 18, height: 16 + pulse * 18)
                    .blur(radius: 5)
                    .position(x: geo.size.width * 0.22, y: geo.size.height / 2 - Harmony.sample(midis, at: elapsed + 0.22 * harmonySpan) * geo.size.height * 0.34)
                Circle().fill(pulse > 0.6 ? gold : color).frame(width: 7 + pulse * 7, height: 7 + pulse * 7)
                    .shadow(color: gold.opacity(pulse), radius: pulse * 8)
                    .position(x: geo.size.width * 0.22, y: geo.size.height / 2 - Harmony.sample(midis, at: elapsed + 0.22 * harmonySpan) * geo.size.height * 0.34)
            }.clipped()
        }
    }
    func repeatShade(_ guides: [(fraction: Double, aligned: Bool)], size: CGSize) -> some View {
        let matches = guides.filter { $0.aligned }
        return Path { path in
            if matches.count >= 2 {
                let start = matches[0].fraction * size.width
                let end = matches[1].fraction * size.width
                path.addRect(CGRect(x: start, y: 0, width: end - start, height: size.height))
            }
        }.fill(gold.opacity(0.055))
    }
    var patternLabel: String {
        let pattern = Harmony.cyclePattern(audio.notes.map(\.midi))
        guard !pattern.isEmpty else { return "Add notes to compare their cycle timing" }
        return "Approximate pattern: " + pattern.map { "\($0.cycles) cycles of \(noteName($0.midi))" }.joined(separator: " ≈ ")
    }
    func alignmentStrip(elapsed: Double) -> some View {
        let midis = audio.notes.map(\.midi)
        let strength = Harmony.alignmentStrength(midis, at: elapsed + 0.22 * harmonySpan)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEAR ALIGNMENT").tracking(1.5)
                Spacer()
                Circle().fill(gold.opacity(0.15 + 0.85 * strength)).frame(width: 8, height: 8)
                    .shadow(color: gold.opacity(strength), radius: strength * 8)
                Text(strength > 0.6 ? "Cycles restarting together" : "Watch the pulse at the cursor")
                    .foregroundStyle(strength > 0.6 ? gold : .secondary)
            }.font(.system(size: 10, weight: .semibold))
            HStack(spacing: 12) {
                Text("Shared timing").font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(width: 145, alignment: .leading)
                GeometryReader { geo in
                    let guides = Harmony.guides(midis, start: elapsed, span: harmonySpan)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.025))
                        repeatShade(guides, size: geo.size)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: geo.size.height))
                            for index in 0..<700 {
                                let fraction = Double(index) / 699
                                let score = Harmony.alignmentStrength(midis, at: elapsed + fraction * harmonySpan)
                                path.addLine(to: CGPoint(x: fraction * geo.size.width, y: geo.size.height * (1 - score * 0.9)))
                            }
                            path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height)); path.closeSubpath()
                        }.fill(LinearGradient(colors: [gold, gold.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                        Rectangle().fill(.white.opacity(0.5)).frame(width: 1)
                            .position(x: geo.size.width * 0.22, y: geo.size.height / 2)
                        Circle().fill(gold).frame(width: 6 + strength * 5, height: 6 + strength * 5)
                            .shadow(color: gold.opacity(strength), radius: 6)
                            .position(x: geo.size.width * 0.22, y: geo.size.height * (1 - strength * 0.9))
                    }.clipped()
                }.frame(height: 44)
            }.padding(.horizontal, 10)
            Text(patternLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(gold)
            Text("Brighter pulses mean closer cycle restarts. The shaded span joins two near-alignment events when visible; the ratio pattern is approximate.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
    func noteLane(_ note: Pitch, elapsed: Double) -> some View {
        HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(note.name) · \(Harmony.frequency(note.midi), specifier: "%.1f") Hz").foregroundStyle(noteColor(note)).fontWeight(.semibold)
                            if note.midi == audio.notes.first?.midi {
                                Text("Lowest note · reference").foregroundStyle(.secondary)
                            } else {
                                let interval = Harmony.interval(from: audio.notes.first!.midi, to: note.midi)
                                Text(interval.name).foregroundStyle(.white.opacity(0.85))
                                Text("≈ \(interval.ratio) · \(interval.centsFromRatio, specifier: "%+.1f") cents").foregroundStyle(.secondary)
                            }
                        }.font(.system(size: 10)).frame(width: 145, alignment: .leading)
                        harmonyLane([note.midi], elapsed: elapsed, color: noteColor(note))
                    }.frame(height: 80).padding(.horizontal, 10)
                        .background(noteColor(note).opacity(0.035))
    }
    var animatedWaves: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: audio.heldNotes.isEmpty)) { timeline in
            let elapsed = motion.time(at: timeline.date)
            VStack(spacing: 0) {
                ForEach(audio.notes) { note in
                    noteLane(note, elapsed: elapsed)
                    Divider().opacity(0.3)
                }
                if audio.notes.count > 1 { alignmentStrip(elapsed: elapsed) }
                if motion.combined && audio.notes.count > 1 {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Combined wave").fontWeight(.semibold)
                            Text("Sum · scaled to fit").foregroundStyle(.secondary)
                        }.font(.system(size: 10)).frame(width: 145, alignment: .leading)
                        harmonyLane(audio.notes.map(\.midi), elapsed: elapsed, color: .white.opacity(0.9))
                    }.frame(height: 90).padding(.horizontal, 10).padding(.top, 8)
                }
            }
        }
    }
    var piano: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("CLICK TO SUSTAIN").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary).tracking(2)
                GeometryReader { geo in
                    let height = geo.size.height / 52
                    let whites = (21...108).filter { ![1,3,6,8,10].contains($0 % 12) }.reversed()
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(whites.enumerated()), id: \.element) { index, midi in
                            let active = audio.notes.contains { $0.midi == midi }
                            RoundedRectangle(cornerRadius: 3).fill(keyFill(midi, black: false))
                                .frame(width: 132, height: max(1, height - 1))
                                .overlay(alignment: .trailing) { if midi % 12 == 0 || active { Text(noteName(midi)).font(.system(size: 9, weight: .semibold)).foregroundStyle(.black.opacity(0.7)).padding(.trailing, 8) } }
                                .overlay(alignment: .trailing) { if audio.heldNotes.contains(midi) { Circle().fill(.black.opacity(0.7)).frame(width: 4, height: 4).padding(.trailing, 2) } }
                                .contentShape(Rectangle()).onTapGesture { audio.toggleNote(midi) }
                                .help("\(noteName(midi)) · click to toggle sustain")
                                .accessibilityLabel("\(noteName(midi)), \(audio.heldNotes.contains(midi) ? "playing" : "off")")
                                .accessibilityAddTraits(.isButton)
                                .offset(y: Double(index) * height)
                        }
                        ForEach((22...106).filter { [1,3,6,8,10].contains($0 % 12) }, id: \.self) { midi in
                            let above = (midi+1...108).filter { ![1,3,6,8,10].contains($0 % 12) }.count
                            let active = audio.notes.contains { $0.midi == midi }
                            RoundedRectangle(cornerRadius: 3).fill(keyFill(midi, black: true))
                                .frame(width: 82, height: height * 0.66)
                                .overlay(alignment: .trailing) { if active { Text(noteName(midi)).font(.system(size: 8, weight: .bold)).foregroundStyle(.black).padding(.trailing, 5) } }
                                .contentShape(Rectangle()).onTapGesture { audio.toggleNote(midi) }
                                .help("\(noteName(midi)) · click to toggle sustain")
                                .accessibilityLabel("\(noteName(midi)), \(audio.heldNotes.contains(midi) ? "playing" : "off")")
                                .accessibilityAddTraits(.isButton)
                                .offset(y: Double(above) * height - height * 0.33)
                        }
                    }
                }.frame(width: 132)
                Text("A0 — C8").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(20).background(Color.white.opacity(0.025))
    }
    var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sonora").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("See the music around you.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop all", action: { audio.stop() }).disabled(audio.heldNotes.isEmpty)
                        .keyboardShortcut(.escape, modifiers: [])
                    Button(action: { audio.microphoneActive ? audio.stop() : audio.start() }) {
                        Label(audio.microphoneActive ? "Pause mic" : "Start microphone", systemImage: audio.microphoneActive ? "pause.fill" : "mic.fill").padding(.horizontal, 12).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DOMINANT NOTE").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                        Text(dominant?.name ?? "Listening…").font(.system(size: 42, weight: .semibold, design: .rounded)).foregroundStyle(gold)
                        Text("Harmony · " + chordName(audio.notes)).font(.system(size: 15, weight: .medium)).foregroundStyle(mint)
                        Text(audio.notes.isEmpty ? "Click piano keys to build a chord" : audio.notes.map(\.name).joined(separator: "  ·  ")).font(.system(size: 14, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(audio.heldNotes.isEmpty ? "INPUT LEVEL" : "INSTRUMENT LEVEL").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                        ProgressView(value: min(1, Double(audio.level) * 8)).tint(mint).frame(width: 110)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(audio.heldNotes.isEmpty ? "SOUND WAVES" : "HARMONY VIEW").tracking(2)
                        Spacer()
                        Text(audio.heldNotes.isEmpty ? "Microphone · combined signal" : "Coloured harmonic orbits · drag to rotate")
                    }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    if audio.heldNotes.isEmpty {
                        GeometryReader { geo in
                            tracePath(audio.waveform, size: geo.size, spectrum: false)
                                .stroke(Color(red: 0.57, green: 0.64, blue: 1), lineWidth: 1.5)
                        }.frame(height: 190).clipped()
                    } else {
                        PhaseSpaceView(notes: audio.notes, motion: motion)
                        Toggle("Explore moving waves", isOn: $motion.showMotion).toggleStyle(.checkbox)
                            .font(.system(size: 12, weight: .medium)).padding(.top, 8)
                        if motion.showMotion {
                            HStack(spacing: 12) {
                                Text("Visualization speed")
                                Text("Slower").foregroundStyle(.secondary)
                                Slider(value: Binding(get: { motion.sliderPosition }, set: { motion.sliderPosition = $0 }), in: -3...0).tint(mint)
                                    .accessibilityLabel("Visualization speed")
                                Text("Faster").foregroundStyle(.secondary)
                                Text(motion.speedLabel).monospacedDigit().frame(width: 90, alignment: .trailing).foregroundStyle(mint)
                            }.font(.system(size: 11)).padding(12)
                                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                            animatedWaves
                            Toggle("Combined wave (white)", isOn: $motion.combined).toggleStyle(.checkbox).font(.system(size: 11))
                            Text("Motion explores phase and wave addition. Its flashes indicate near cycle restarts, not musical harmony.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("FREQUENCY SPECTRUM").tracking(2); Spacer(); Text("27.5 Hz – 16 kHz · logarithmic") }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack {
                            Path { p in for i in 0...4 { let y = geo.size.height * Double(i) / 4; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) } }.stroke(.white.opacity(0.07), lineWidth: 1)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: geo.size.height))
                                for (i, value) in audio.spectrum.enumerated() { p.addLine(to: CGPoint(x: geo.size.width * Double(i) / 399, y: geo.size.height * (1 - Double(value)))) }
                                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height)); p.closeSubpath()
                            }.fill(LinearGradient(colors: [gold.opacity(0.65), mint.opacity(0.25), Color.blue.opacity(0.02)], startPoint: .top, endPoint: .bottom)).opacity(audio.heldNotes.isEmpty ? 1 : 0.25)
                            Path { p in for (i, value) in audio.spectrum.enumerated() { let point = CGPoint(x: geo.size.width * Double(i) / 399, y: geo.size.height * (1 - Double(value))); if i == 0 { p.move(to: point) } else { p.addLine(to: point) } } }.stroke(LinearGradient(colors: [gold, mint, Color.blue.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 2).opacity(audio.heldNotes.isEmpty ? 1 : 0.2)
                            ForEach(audio.notes.filter { audio.toneTraces[$0.midi] != nil }) { note in
                                tracePath(audio.toneTraces[note.midi]!.spectrum, size: geo.size, spectrum: true)
                                    .stroke(noteColor(note), lineWidth: 2)
                            }
                            ForEach(audio.notes) { note in
                                let frequency = 440 * pow(2, Double(note.midi - 69) / 12)
                                let x = geo.size.width * log(frequency / 27.5) / log(16000 / 27.5)
                                let leading = note.midi == dominant?.midi
                                VStack(spacing: 3) {
                                    Text(leading ? "● " + note.name : note.name)
                                        .font(.system(size: leading ? 13 : 10, weight: .bold)).padding(leading ? 6 : 4)
                                        .background(noteColor(note), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.black)
                                    Rectangle().fill(LinearGradient(colors: [noteColor(note).opacity(leading ? 0.8 : 0.3), .clear], startPoint: .top, endPoint: .bottom)).frame(width: leading ? 3 : 1)
                                }.opacity(leading ? 1 : 0.35 + 0.45 * prominence(note))
                                    .position(x: x, y: geo.size.height / 2)
                            }
                        }
                    }.frame(minHeight: 170)
                    HStack { ForEach(["27.5", "100", "400", "1.6k", "6.4k", "16k Hz"], id: \.self) { label in Text(label); if label != "16k Hz" { Spacer() } } }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                HStack {
                    Circle().fill(audio.running ? mint : .gray).frame(width: 6, height: 6)
                    Text(audio.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Mic threshold").font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: $audio.sensitivity, in: 0.07...0.45).frame(width: 95).tint(mint).disabled(!audio.microphoneActive).onChange(of: audio.sensitivity) { _ in audio.updateSensitivity() }.help("Lower values detect quieter notes; higher values reject more overtones and noise.")
                }
                Text("Click keys to sustain pure tones; click again to release. Esc stops all notes. Starting the microphone switches away from the instrument.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}

