import Foundation

extension LiveInk {
    /// The spoken words with the numbers of the strokes drawn while they were said put in where each
    /// was drawn, or nil when the note is not as it was said or no stroke was drawn while speaking.
    func numberedNote(_ spoken: (words: [SpokenWord], began: Date)?, packet: LivePacket) -> String? {
        guard let spoken else { return nil }
        let strokes = packet.numbers.compactMap { id, number -> SpokenNote.Stroke? in
            guard let times = strokeTimes[id] else { return nil }
            let stroke = SpokenNote.Stroke(number: number, start: times.began.timeIntervalSince(spoken.began),
                                           end: times.ended.timeIntervalSince(spoken.began))
            // A stroke that ended before listening began belongs to an earlier note.
            return stroke.end >= 0 ? stroke : nil
        }
        guard !strokes.isEmpty else { return nil }
        Log.write("[speech] numbered strokes=\(strokes.count)")
        return SpokenNote.marked(spoken.words, strokes: strokes)
    }
}
