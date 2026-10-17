import Foundation

struct Pitch: Identifiable {
    let midi: Int
    let strength: Float
    var id: Int { midi }
    var name: String { noteName(midi) }
}
func noteName(_ midi: Int) -> String {
    let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    return "\(names[(midi % 12 + 12) % 12])\(midi / 12 - 1)"
}
func chordName(_ notes: [Pitch]) -> String {
    let pcs = Set(notes.map { $0.midi % 12 })
    guard pcs.count >= 2 else { return notes.first?.name ?? "Listening…" }
    let patterns: [(String, Set<Int>)] = [("maj7", [0,4,7,11]), ("m7", [0,3,7,10]), ("7", [0,4,7,10]), (" major", [0,4,7]), (" minor", [0,3,7]), (" diminished", [0,3,6]), (" augmented", [0,4,8]), ("sus2", [0,2,7]), ("sus4", [0,5,7]), ("5", [0,7])]
    for (suffix, pattern) in patterns {
        for root in pcs.sorted() {
            if Set(pattern.map { (root + $0) % 12 }) == pcs { return String(noteName(root + 60).dropLast()) + suffix }
        }
    }
    return "\(pcs.count)-note harmony"
}

