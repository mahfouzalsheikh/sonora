import SwiftUI
import AppKit

// Render the actual app view with reproducible, silent demonstration state.
// No microphone permission, audio output, or desktop pixels are captured.
enum ScreenshotExporter {
    static func export(to directory: String) {
        let examples = [("perfect-fifth", [72,79]), ("major-triad", [72,76,79])]
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, midis) in examples {
                let audio = Analyzer()
                audio.running = true
                audio.heldNotes = Set(midis)
                audio.notes = midis.map { Pitch(midi: $0, strength: 1) }
                audio.status = "Keyboard instrument · \(midis.count) sustained notes · click a key again to release"
                audio.level = 0.07
                for midi in midis { audio.toneTraces[midi] = ToneTrace(buffer: Analyzer.toneBuffer(midi: midi)) }
                audio.spectrum = (0..<400).map { index in audio.toneTraces.values.map { $0.spectrum[index] }.max() ?? 0 }
                let view = NSHostingView(rootView: ContentView(audio: audio))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1220), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                window.orderBack(nil)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "Screenshot", code: 1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Screenshot", code: 2) }
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                window.orderOut(nil)
                print("Exported \(name).png")
            }
            exit(0)
        } catch { fputs("Screenshot export failed: \(error)\n", stderr); exit(1) }
    }
}
