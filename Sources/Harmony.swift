import Foundation

struct NotePair: Identifiable {
    let lower: Int
    let upper: Int
    var id: Int { lower * 128 + upper }
}
struct MusicalInterval {
    let name: String
    let numerator: Int
    let denominator: Int
    let centsFromRatio: Double
    var ratio: String { "\(numerator):\(denominator)" }
}
enum Harmony {
    static func pairs(_ midis: [Int]) -> [NotePair] {
        let sorted = Array(Set(midis)).sorted()
        return sorted.enumerated().flatMap { index, lower in
            sorted.dropFirst(index + 1).map { NotePair(lower: lower, upper: $0) }
        }
    }
    static func fittedPattern(_ midis: [Int]) -> [(midi: Int, cycles: Int)] {
        let pattern = cyclePattern(midis)
        return pattern.allSatisfy { $0.cycles <= 24 } ? pattern : []
    }
    static func chordExplanation(_ midis: [Int]) -> String {
        let pcs = Set(midis.map { $0 % 12 })
        guard pcs.count > 1 else { return midis.count > 1 ? "Octave doubling: the same pitch class in different registers." : "Add another note to compare intervals and cycles." }
        let structures: [(Set<Int>, String)] = [
            ([0,4,7,11], "Major seventh chord: root, major third, perfect fifth, and major seventh."),
            ([0,3,7,10], "Minor seventh chord: root, minor third, perfect fifth, and minor seventh."),
            ([0,4,7,10], "Dominant seventh chord: root, major third, perfect fifth, and minor seventh."),
            ([0,4,7], "Major triad: a major third and perfect fifth above its root."),
            ([0,3,7], "Minor triad: a minor third and perfect fifth above its root."),
            ([0,3,6], "Diminished triad: two stacked minor thirds, with a diminished fifth above the root."),
            ([0,4,8], "Augmented triad: two stacked major thirds."),
            ([0,2,7], "Suspended second: a major second and perfect fifth above the root."),
            ([0,5,7], "Suspended fourth: a perfect fourth and perfect fifth above the root."),
            ([0,7], "A root and perfect fifth; there is no third to distinguish major from minor.")
        ]
        for (pattern, explanation) in structures {
            for root in pcs.sorted() where Set(pattern.map { ($0 + root) % 12 }) == pcs {
                return explanation
            }
        }
        return "Explore the intervals below. This selection has no match in the app’s chord dictionary; that does not make it musically wrong."
    }
    static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
    static func interval(from root: Int, to note: Int) -> MusicalInterval {
        let distance = max(0, note - root)
        let names = ["Unison", "Minor second", "Major second", "Minor third", "Major third", "Perfect fourth", "Tritone", "Perfect fifth", "Minor sixth", "Major sixth", "Minor seventh", "Major seventh"]
        let ratios = [(1,1),(16,15),(9,8),(6,5),(5,4),(4,3),(45,32),(3,2),(8,5),(5,3),(9,5),(15,8)]
        let octaves = distance / 12
        let pair = ratios[distance % 12]
        let numerator = pair.0 * (1 << octaves)
        let denominator = pair.1
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = gcd(numerator, denominator)
        let name: String
        if distance == 12 { name = "Octave" }
        else if distance > 12 { name = distance % 12 == 0 ? "\(octaves) octaves" : "\(names[distance % 12]) + \(octaves) oct." }
        else { name = names[distance] }
        let cents = Double(distance) * 100 - 1200 * log2(Double(numerator) / Double(denominator))
        return MusicalInterval(name: name, numerator: numerator / divisor, denominator: denominator / divisor, centsFromRatio: cents)
    }
    static func sample(_ midis: [Int], at time: Double) -> Double {
        midis.reduce(0) { $0 + sin(2 * .pi * frequency($1) * time) } / Double(max(1, midis.count))
    }
    // A continuous closeness value: 1 at a shared cycle restart, fading as phases diverge.
    static func alignmentStrength(_ midis: [Int], at time: Double) -> Double {
        guard midis.count > 1 else { return 0 }
        let distance = midis.map { midi -> Double in
            let phase = frequency(midi) * time
            return abs(phase - phase.rounded())
        }.max() ?? 0.5
        return exp(-0.5 * pow(distance / 0.045, 2))
    }
    static func cyclePattern(_ midis: [Int]) -> [(midi: Int, cycles: Int)] {
        guard let root = midis.min(), midis.count > 1 else { return [] }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let intervals = midis.sorted().map { interval(from: root, to: $0) }
        var count = 1
        for item in intervals {
            count = count / gcd(count, item.denominator) * item.denominator
            if count > 64 { return [] }
        }
        return zip(midis.sorted(), intervals).map { ($0.0, count / $0.1.denominator * $0.1.numerator) }
    }
    // Test the actual equal-tempered phases, rather than drawing ideal-ratio alignments.
    static func aligned(_ midis: [Int], at time: Double) -> Bool {
        midis.allSatisfy {
            let cycles = frequency($0) * time
            return abs(cycles - cycles.rounded()) <= 0.045
        }
    }
    static func guides(_ midis: [Int], start: Double, span: Double) -> [(fraction: Double, aligned: Bool)] {
        guard let root = midis.min() else { return [] }
        let frequency = frequency(root)
        let first = Int(ceil(start * frequency))
        let last = Int(floor((start + span) * frequency))
        guard first <= last else { return [] }
        return (first...last).map { cycle in
            let time = Double(cycle) / frequency
            return ((time - start) / span, midis.count > 1 && aligned(midis, at: time))
        }
    }
}
