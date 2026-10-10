import XCTest
@testable import ScorecardCore

final class AudioTurnsTests: XCTestCase {
    func pcm(seconds: Double, sample: Int16) -> Data {
        var samples = Array(repeating: sample.littleEndian, count: Int(seconds * 24_000))
        return samples.withUnsafeMutableBytes { Data($0) }
    }
    func testSilenceNeverCreatesAnEmptyTranscriptTurn() {
        var detector = SpeechTurnBuffer()
        for i in 0..<100 { XCTAssertNil(detector.ingest(pcm(seconds: 0.1, sample: 0), startSeconds: Double(i) / 10)) }
        XCTAssertNil(detector.flush())
    }
    func testSpeechEndsAfterSilenceAndUsesLastVoiceTime() {
        var detector = SpeechTurnBuffer()
        _ = detector.ingest(pcm(seconds: 0.2, sample: 0), startSeconds: 0)
        _ = detector.ingest(pcm(seconds: 0.3, sample: 2000), startSeconds: 0.2)
        XCTAssertNil(detector.ingest(pcm(seconds: 0.3, sample: 0), startSeconds: 0.5))
        let turn = detector.ingest(pcm(seconds: 0.3, sample: 0), startSeconds: 0.8)
        XCTAssertEqual(turn?.startSeconds, 0)
        XCTAssertEqual(turn?.endSeconds, 0.5)
        XCTAssertNil(detector.flush())
    }
    func testLongSpeechHasBoundedChunks() {
        var detector = SpeechTurnBuffer()
        var turns: [AudioTurn] = []
        for i in 0..<100 {
            if let turn = detector.ingest(pcm(seconds: 0.1, sample: 2000), startSeconds: Double(i) / 10) { turns.append(turn) }
        }
        XCTAssertEqual(turns.count, 3)
        XCTAssertTrue(turns.allSatisfy { $0.pcm16.count <= 148_800 })
        XCTAssertNotNil(detector.flush())
    }
    func testOutOfOrderCompletionsRetainIdentityAndTime() {
        var tracker = AudioCommitTracker()
        let a = AudioTurn(pcm16: Data(), startSeconds: 1, endSeconds: 2)
        let b = AudioTurn(pcm16: Data(), startSeconds: 3, endSeconds: 4)
        tracker.enqueue(a); tracker.enqueue(b)
        XCTAssertTrue(tracker.acknowledged(itemID: "first"))
        XCTAssertTrue(tracker.acknowledged(itemID: "second"))
        XCTAssertFalse(tracker.acknowledged(itemID: "extra"))
        XCTAssertEqual(tracker.finish(itemID: "second")?.id, b.id)
        XCTAssertEqual(tracker.finish(itemID: "first")?.startSeconds, 1)
        XCTAssertNil(tracker.finish(itemID: "first"))
        XCTAssertEqual(tracker.pendingCount, 0)
    }
}
