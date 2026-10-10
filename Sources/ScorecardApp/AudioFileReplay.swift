@preconcurrency import AVFoundation
import Foundation
import ScorecardCore

/// Feeds a selected recording at its original pace through the same audio channel
/// as live capture. Reads bounded chunks, never records or opens a microphone.
actor AudioFileReplay {
    private let file: AVAudioFile
    let duration: Double

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0, duration <= 300,
              (8000...192000).contains(format.sampleRate),
              (1...8).contains(format.channelCount) else {
            throw DatabaseError(message: "Choose an audio file up to five minutes long, with 1–8 channels and an 8–192 kHz sample rate.")
        }
        self.file = file; self.duration = duration
    }

    func run(channel: any AudioChannel) async throws {
        let clockStart = ContinuousClock.now
        let wallStart = Date()
        let format = file.processingFormat
        let chunkFrames = AVAudioFrameCount(format.sampleRate / 10)
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let count = min(AVAudioFramePosition(chunkFrames), file.length - file.framePosition)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw DatabaseError(message: "The audio file could not be decoded.")
            }
            try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
            guard buffer.frameLength > 0 else {
                throw DatabaseError(message: "The audio file ended before its declared duration.")
            }
            let elapsed = Double(file.framePosition) / format.sampleRate
            let mono = try AudioBufferCanonicalizer.makeCanonicalMonoBuffer(from: buffer)
            try await ContinuousClock().sleep(until: clockStart + .seconds(elapsed))
            try Task.checkCancellation()
            await channel.consume(mono, capturedAt: wallStart.addingTimeInterval(elapsed))
        }
    }
}
