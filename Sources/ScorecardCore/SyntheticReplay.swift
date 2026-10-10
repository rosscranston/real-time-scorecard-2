import Foundation
import NaturalLanguage

public struct SyntheticCallPack: Decodable, Sendable {
    public var calls: [SyntheticCall]
}
public struct SyntheticCall: Decodable, Sendable {
    public struct Turn: Decodable, Sendable {
        public var turn: Int
        public var speaker: String
        public var channel: String
        public var text: String
        public var timestampSeconds: Double
    }
    public var id: String
    public var title: String
    public var turns: [Turn]
    /// Sentence segmentation preserves punctuation and quotes; no answer keys enter inference.
    public func sentences(callID: UUID, startingSequence: Int = 1) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        for turn in turns {
            let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = turn.text
            tokenizer.enumerateTokens(in: turn.text.startIndex..<turn.text.endIndex) { range, _ in
                let sentence = String(turn.text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    entries.append(TranscriptEntry(callID: callID, sequence: startingSequence + entries.count,
                        speaker: turn.channel == "ROSS" ? .salesperson : .customer,
                        text: sentence, seconds: turn.timestampSeconds))
                }
                return true
            }
        }
        return entries
    }
}
