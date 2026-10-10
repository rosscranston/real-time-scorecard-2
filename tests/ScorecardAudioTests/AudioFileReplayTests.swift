import XCTest
@preconcurrency import AVFoundation
@testable import ScorecardApp

private actor RecordingAudioChannel: AudioChannel {
    struct Snapshot: Sendable {
        var frames = 0
        var chunks = 0
        var peak: Float = 0
        var channels = Set<AVAudioChannelCount>()
        var endTimes: [Date] = []
    }
    private var recorded = Snapshot()
    func prepare() async throws {}
    func stop() async {}
    func consume(_ buffer: AVAudioPCMBuffer, capturedAt: Date) async {
        recorded.frames += Int(buffer.frameLength)
        recorded.chunks += 1
        recorded.channels.insert(buffer.format.channelCount)
        recorded.endTimes.append(capturedAt)
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) { recorded.peak = max(recorded.peak, abs(samples[index])) }
        }
    }
    func snapshot() -> Snapshot { recorded }
}

final class AudioFileReplayTests: XCTestCase {
    private func fixture(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scorecard-audio-test-\(UUID()).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 48000)
        if frames > 0 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            for index in 0..<Int(frames) {
                buffer.floatChannelData![0][index] = 0
                buffer.floatChannelData![1][index] = 0.4
            }
            try file.write(from: buffer)
        }
        return url
    }

    func testPacedReplayPreservesFramesAndSelectsAudibleChannel() async throws {
        let url = try fixture(seconds: 0.24)
        defer { try? FileManager.default.removeItem(at: url) }
        let replay = try AudioFileReplay(url: url)
        let channel = RecordingAudioChannel()
        let start = Date()
        try await replay.run(channel: channel)
        let result = await channel.snapshot()
        XCTAssertEqual(result.frames, 11520)
        XCTAssertEqual(result.chunks, 3)
        XCTAssertEqual(result.channels, [1])
        XCTAssertEqual(result.peak, 0.4, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.23)
        XCTAssertEqual(result.endTimes[1].timeIntervalSince(result.endTimes[0]), 0.1, accuracy: 0.001)
        XCTAssertEqual(result.endTimes[2].timeIntervalSince(result.endTimes[1]), 0.04, accuracy: 0.001)
    }

    func testCancellationStopsBeforeSendingMoreAudio() async throws {
        let url = try fixture(seconds: 0.8)
        defer { try? FileManager.default.removeItem(at: url) }
        let replay = try AudioFileReplay(url: url)
        let channel = RecordingAudioChannel()
        let task = Task { try await replay.run(channel: channel) }
        try await Task.sleep(for: .milliseconds(140))
        task.cancel()
        do { try await task.value; XCTFail("Cancelled replay must terminate") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let stopped = await channel.snapshot()
        XCTAssertLessThan(stopped.frames, 38400)
        try await Task.sleep(for: .milliseconds(150))
        let later = await channel.snapshot()
        XCTAssertEqual(later.frames, stopped.frames)
    }

    func testEmptyRecordingIsRejectedBeforeOpeningAChannel() throws {
        let url = try fixture(seconds: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try AudioFileReplay(url: url))
    }
}
