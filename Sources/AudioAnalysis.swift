import SwiftUI
import AVFoundation
import Accelerate

func fftMagnitudes(_ frame: [Float]) -> [Float] {
    let n = frame.count
    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    var real = zip(frame, window).map(*)
    var imag = [Float](repeating: 0, count: n)
    guard let fft = vDSP_create_fftsetup(13, FFTRadix(kFFTRadix2)) else { return [Float](repeating: 0, count: n / 2) }
    var magnitudes = [Float](repeating: 0, count: n / 2)
    real.withUnsafeMutableBufferPointer { r in imag.withUnsafeMutableBufferPointer { i in
        var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
        vDSP_fft_zip(fft, &split, 1, 13, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
    } }
    vDSP_destroy_fftsetup(fft)
    return magnitudes
}
struct ToneTrace {
    let waveform: [Float]
    let spectrum: [Float]
    init(buffer: AVAudioPCMBuffer) {
        let count = Int(buffer.frameLength)
        let data = buffer.floatChannelData![0]
        let frame = (0..<8192).map { data[$0 % count] }
        waveform = (0..<400).map { frame[$0 * 4] }
        let magnitudes = fftMagnitudes(frame)
        spectrum = (0..<400).map { index in
            let low = 27.5 * pow(16000 / 27.5, Double(index) / 400)
            let high = 27.5 * pow(16000 / 27.5, Double(index + 1) / 400)
            let a = max(1, min(4095, Int(low * 8192 / buffer.format.sampleRate)))
            let b = max(a, min(4095, Int(high * 8192 / buffer.format.sampleRate)))
            let amplitude = (magnitudes[a...b].max() ?? 0) / 8192
            return max(0, min(1, (20 * log10(max(amplitude, 0.000001)) + 85) / 70))
        }
    }
}

final class Analyzer: ObservableObject {
    @Published var spectrum = [Float](repeating: 0, count: 400)
    @Published var waveform = [Float](repeating: 0, count: 400)
    @Published var notes: [Pitch] = []
    @Published var running = false
    @Published var toneTraces: [Int: ToneTrace] = [:]
    @Published var heldNotes: Set<Int> = []
    @Published var microphoneActive = false
    @Published var status = "Start listening to use your microphone"
    @Published var level: Float = 0
    @Published var sensitivity: Double = 0.18
    private var engine: AVAudioEngine?
    private let queue = DispatchQueue(label: "harmonics.analysis")
    private var pending = [Float]()
    private var smoothed = [Float](repeating: 0, count: 400)
    private var history = [Int: Float]()
    private var threshold: Float = 0.18
    private var generation = 0
    private var players = [Int: AVAudioPlayerNode]()
    private var synthesisNotes: [Pitch]? = nil

    // Whole cycles make the looping sine tone continuous at the buffer boundary.
    static func toneBuffer(midi: Int, rate: Double = 48000) -> AVAudioPCMBuffer {
        let frequency = 440 * pow(2, Double(midi - 69) / 12)
        let cycles = max(1, Int(frequency.rounded()))
        let count = Int((rate * Double(cycles) / frequency).rounded())
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let data = buffer.floatChannelData![0]
        for i in 0..<count { data[i] = Float(0.1 * sin(2 * .pi * Double(cycles) * Double(i) / Double(count))) }
        return buffer
    }
    func toggleNote(_ midi: Int) {
        if microphoneActive { stop() }
        if heldNotes.contains(midi) {
            players[midi]?.stop()
            if let player = players.removeValue(forKey: midi) { engine?.detach(player) }
            toneTraces.removeValue(forKey: midi)
            heldNotes.remove(midi)
            if heldNotes.isEmpty { stop(); return }
        } else {
            let audio = engine ?? AVAudioEngine()
            let player = AVAudioPlayerNode()
            let buffer = Self.toneBuffer(midi: midi)
            audio.attach(player)
            audio.connect(player, to: audio.mainMixerNode, format: buffer.format)
            if engine == nil {
                generation += 1
                let token = generation
                queue.async { self.synthesisNotes = []; self.pending.removeAll(); self.history.removeAll() }
                audio.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
                    guard let self, let channel = buffer.floatChannelData?[0] else { return }
                    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                    let rate = buffer.format.sampleRate
                    self.queue.async { self.process(samples, rate: rate, token: token) }
                }
                do { try audio.start(); engine = audio; running = true }
                catch {
                    audio.mainMixerNode.removeTap(onBus: 0)
                    status = "Could not start instrument: \(error.localizedDescription)"
                    return
                }
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            players[midi] = player
            toneTraces[midi] = ToneTrace(buffer: buffer)
            heldNotes.insert(midi)
            player.play()
        }
        engine?.mainMixerNode.outputVolume = 1 / sqrt(Float(max(1, heldNotes.count)))
        let pitches = heldNotes.sorted().map { Pitch(midi: $0, strength: 1) }
        queue.async { self.synthesisNotes = pitches }
        notes = pitches
        status = "Keyboard instrument · \(heldNotes.count) sustained note\(heldNotes.count == 1 ? "" : "s") · click a key again to release"
    }
    func start() {
        if !microphoneActive { stop() }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in DispatchQueue.main.async { if granted { self.begin() } else { self.status = "Microphone access denied. Enable Harmonics in System Settings → Privacy & Security → Microphone." } } }
        default: status = "Enable Harmonics in System Settings → Privacy & Security → Microphone."
        }
    }
    func stop() {
        generation += 1
        engine?.stop()
        if microphoneActive { engine?.inputNode.removeTap(onBus: 0) }
        else if engine != nil { engine?.mainMixerNode.removeTap(onBus: 0) }
        players.removeAll(); heldNotes.removeAll(); toneTraces.removeAll(); engine = nil
        running = false; microphoneActive = false; notes = []; level = 0; status = "Click piano keys to play, or start the microphone"
        spectrum = [Float](repeating: 0, count: 400); waveform = spectrum
        queue.async { self.pending.removeAll(); self.history.removeAll(); self.smoothed = [Float](repeating: 0, count: 400); self.synthesisNotes = nil }
    }
    func updateSensitivity() { let value = Float(sensitivity); queue.async { self.threshold = value } }
    private func begin() {
        guard !running else { return }
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { status = "No microphone is available."; return }
        generation += 1
        let token = generation
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let rate = format.sampleRate
            self.queue.async { self.process(samples, rate: rate, token: token) }
        }
        do { try audio.start(); engine = audio; running = true; microphoneActive = true; status = "Listening to your default microphone" }
        catch { input.removeTap(onBus: 0); status = "Could not start microphone: \(error.localizedDescription)" }
    }
    func process(_ samples: [Float], rate: Double, token: Int) {
        let n = 8192
        pending.append(contentsOf: samples)
        guard pending.count >= n else { return }
        let frame = Array(pending.suffix(n))
        pending = Array(frame.suffix(n - 2048))
        let rms = sqrt(frame.reduce(Float(0)) { $0 + $1 * $1 } / Float(n))
        let magnitudes = fftMagnitudes(frame)
        let maximum = magnitudes.max() ?? 1
        var bins = [Float](repeating: 0, count: 400)
        for j in 0..<400 {
            let low = 27.5 * pow(16000 / 27.5, Double(j) / 400)
            let high = 27.5 * pow(16000 / 27.5, Double(j + 1) / 400)
            let a = max(1, min(n / 2 - 1, Int(low * Double(n) / rate)))
            let b = max(a, min(n / 2 - 1, Int(high * Double(n) / rate)))
            let amplitude = (magnitudes[a...b].max() ?? 0) / Float(n)
            bins[j] = max(0, min(1, (20 * log10(max(amplitude, 0.000001)) + 85) / 70))
            smoothed[j] = smoothed[j] * 0.55 + bins[j] * 0.45
        }
        var candidates: [(Int, Float, Double)] = []
        if rms > 0.002 {
            for k in 5..<(n / 2 - 1) where magnitudes[k] > maximum * threshold && magnitudes[k] > magnitudes[k-1] && magnitudes[k] >= magnitudes[k+1] {
                let left = log(max(magnitudes[k-1], 1e-10)), center = log(max(magnitudes[k], 1e-10)), right = log(max(magnitudes[k+1], 1e-10))
                let denominator = left - 2 * center + right
                let offset = abs(denominator) > 1e-8 ? Double(0.5 * (left - right) / denominator) : 0
                let frequency = (Double(k) + offset) * rate / Double(n)
                let midi = Int((69 + 12 * log2(frequency / 440)).rounded())
                if (21...108).contains(midi) { candidates.append((midi, magnitudes[k] / maximum, frequency)) }
            }
        }
        candidates.sort { $0.2 < $1.2 }
        var fundamentals: [(Int, Float, Double)] = []
        for candidate in candidates {
            let overtone = fundamentals.contains { lower in
                let ratio = candidate.2 / lower.2, harmonic = ratio.rounded()
                return harmonic >= 2 && harmonic <= 8 && abs(12 * log2(ratio / harmonic)) < 0.3 && candidate.1 < lower.1 * 1.3
            }
            if !overtone { fundamentals.append(candidate) }
        }
        var current = [Int: Float]()
        for item in fundamentals.sorted(by: { $0.1 > $1.1 }).prefix(6) { current[item.0] = max(current[item.0] ?? 0, item.1) }
        for key in Set(history.keys).union(current.keys) { history[key] = (history[key] ?? 0) * 0.65 + (current[key] ?? 0) * 0.35 }
        history = history.filter { $0.value > 0.06 }
        let pitches = synthesisNotes ?? history.filter { $0.value > 0.16 }.map { Pitch(midi: $0.key, strength: $0.value) }.sorted { $0.midi < $1.midi }
        let wave = (0..<400).map { frame[$0 * 4] }
        let result = smoothed
        DispatchQueue.main.async {
            guard self.running, token == self.generation else { return }
            self.spectrum = result; self.waveform = wave; self.notes = pitches; self.level = rms
        }
    }
}

