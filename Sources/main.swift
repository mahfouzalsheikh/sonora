import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--export-screenshots"), CommandLine.arguments.count > index + 1 {
            ScreenshotExporter.export(to: CommandLine.arguments[index + 1])
            return
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Sonora"
        window.contentView = NSHostingView(rootView: ContentView())
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
if CommandLine.arguments.contains("--harmony-test") {
    precondition(Harmony.interval(from: 60, to: 72).ratio == "2:1")
    precondition(Harmony.interval(from: 60, to: 67).ratio == "3:2")
    precondition(Harmony.interval(from: 60, to: 64).ratio == "5:4")
    precondition(Harmony.interval(from: 60, to: 61).name == "Minor second")
    precondition(Harmony.interval(from: 60, to: 84).ratio == "4:1")
    let period = 1 / Harmony.frequency(60)
    precondition(Harmony.aligned([60,72], at: period))
    precondition(!Harmony.aligned([60,67], at: period))
    precondition(Harmony.aligned([60,67], at: period * 2))
    precondition(!Harmony.aligned([60,61], at: period * 2))
    let guides = Harmony.guides([60,72], start: 0.1, span: period * 8)
    precondition(guides.count == 8 && guides.allSatisfy { $0.aligned && (0...1).contains($0.fraction) })
    precondition(abs(Harmony.sample([60,72], at: period / 4) - 0.5) < 1e-9)
    precondition(abs(Harmony.alignmentStrength([60,72], at: period) - 1) < 1e-9)
    precondition(Harmony.alignmentStrength([60,67], at: period) < 0.01)
    precondition(Harmony.alignmentStrength([60,67], at: 2 * period) > 0.99)
    precondition(Harmony.alignmentStrength([60], at: 0) == 0)
    precondition(Harmony.cyclePattern([60,67]).map(\.cycles) == [2,3])
    precondition(Harmony.cyclePattern([60,64,67]).map(\.cycles) == [4,5,6])
    precondition(Harmony.fittedPattern([60,64,67]).map(\.cycles) == [4,5,6])
    precondition(Harmony.fittedPattern([60,61,62]).isEmpty)
    precondition(Harmony.pairs([60,64,67]).count == 3)
    precondition(Harmony.pairs([60,60,64]).count == 1)
    precondition(Harmony.chordExplanation([60,64,67]).hasPrefix("Major triad"))
    precondition(Harmony.chordExplanation([57,60,64]).hasPrefix("Minor triad"))
    let point = PhaseSpace.point(notes: [60,64,67], time: period / 4)
    precondition(abs(point.x - 1) < 1e-9)
    precondition(abs(point.y - sin(2 * .pi * Harmony.frequency(64) * period / 4)) < 1e-9)
    precondition(abs(point.z - sin(2 * .pi * Harmony.frequency(67) * period / 4)) < 1e-9)
    precondition(PhaseSpace.point(notes: [60,64], time: period).z == 0)
    let projected = PhaseSpace.project(point, yaw: 0.4, pitch: 0.3, size: CGSize(width: 700, height: 370))
    precondition(projected.x.isFinite && projected.y.isFinite)
    let extra = PhaseSpace.point(notes: [60,64,67,72], time: period / 4)
    precondition(extra.x.isFinite && extra.y.isFinite && extra.z.isFinite)
    for midi in [72, 75, 79, 73] {
        let start = PhaseSpace.orbit(note: midi, root: 72, fraction: 0, fitted: true)
        let end = PhaseSpace.orbit(note: midi, root: 72, fraction: 1, fitted: true)
        precondition(abs(start.x - end.x) + abs(start.y - end.y) + abs(start.z - end.z) < 1e-8)
    }
    precondition(Harmony.interval(from: 72, to: 79).numerator == 3)
    precondition(Harmony.interval(from: 72, to: 75).numerator == 6)
    precondition(Harmony.interval(from: 72, to: 73).numerator == 16)
    let actualEnd = PhaseSpace.orbit(note: 79, root: 72, fraction: 1, fitted: false)
    precondition(abs(actualEnd.z) > 0.001)
    print("PASS interval labels, ratios, phase alignment, continuous pulse strength, cycle counts, guides, and summation")
    exit(0)
}
if CommandLine.arguments.contains("--instrument-test") {
    let analyzer = Analyzer()
    analyzer.toggleNote(60); analyzer.toggleNote(64); analyzer.toggleNote(67); analyzer.toggleNote(72)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
    guard analyzer.running, !analyzer.microphoneActive,
          analyzer.notes.map(\.midi) == [60, 64, 67, 72],
          analyzer.toneTraces.count == 4,
          analyzer.toneTraces.values.allSatisfy({ $0.waveform.count == 400 && ($0.spectrum.max() ?? 0) > 0.1 }),
          analyzer.level > 0.01, (analyzer.spectrum.max() ?? 0) > 0.1 else {
        print("FAIL instrument output: \(analyzer.status), level \(analyzer.level), notes \(analyzer.notes.map(\.midi))")
        analyzer.stop(); exit(1)
    }
    print("PASS sustained C major with octave: output audio feeds spectrum and exact note labels")
    analyzer.toggleNote(64)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    guard analyzer.toneTraces[64] == nil, !analyzer.heldNotes.contains(64), !analyzer.notes.contains(where: { $0.midi == 64 }) else { print("FAIL release"); exit(1) }
    print("PASS toggle release")
    analyzer.stop()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    guard !analyzer.running, analyzer.heldNotes.isEmpty, analyzer.toneTraces.isEmpty, analyzer.notes.isEmpty, analyzer.level == 0 else { print("FAIL stop all"); exit(1) }
    print("PASS stop all and clear visualization")
    analyzer.toggleNote(21); analyzer.toggleNote(108)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    guard analyzer.notes.map(\.midi) == [21,108], analyzer.level > 0 else { print("FAIL restart / range"); exit(1) }
    analyzer.toggleNote(21); analyzer.toggleNote(108)
    guard !analyzer.running, analyzer.heldNotes.isEmpty else { print("FAIL last key release"); exit(1) }
    print("PASS restart, full keyboard range, and final key release")
    exit(0)
}
if CommandLine.arguments.contains("--self-test") {
    let tests: [(String, [Int])] = [("A4", [69]), ("C major", [60,64,67]), ("A minor", [57,60,64]), ("silence", [])]
    for (name, expected) in tests {
        let analyzer = Analyzer()
        analyzer.running = true
        for step in 0..<16 {
            let samples = (0..<8192).map { index -> Float in
                let t = Double(index + step * 2048) / 48000
                return expected.reduce(Float(0)) { sum, midi in
                    let f = 440 * pow(2, Double(midi - 69) / 12)
                    return sum + Float(0.12 * sin(2 * .pi * f * t) + 0.035 * sin(4 * .pi * f * t))
                }
            }
            analyzer.process(samples, rate: 48000, token: 0)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        let actual = analyzer.notes.map(\.midi)
        guard actual == expected.sorted() else { print("FAIL \(name): expected \(expected), got \(actual)"); exit(1) }
        print("PASS \(name): \(actual) / \(chordName(analyzer.notes))")
    }
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let menu = NSMenu()
let appMenu = NSMenuItem()
menu.addItem(appMenu)
let submenu = NSMenu()
submenu.addItem(withTitle: "Quit Sonora", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenu.submenu = submenu
app.mainMenu = menu
app.run()
