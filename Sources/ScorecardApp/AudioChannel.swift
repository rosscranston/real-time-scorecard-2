@preconcurrency import AVFoundation
import ScorecardCore
import Foundation

protocol AudioChannel: Sendable {
    func prepare() async throws
    func consume(_ buffer: AVAudioPCMBuffer, capturedAt: Date) async
    func stop() async
}

actor CloudSpeechChannel: AudioChannel {
    private let transcriber: OpenAITranscriber
    private let onError: @Sendable (String) -> Void
    private let origin: Date
    private var vad = SpeechTurnBuffer()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
    private var failed = false
    init(key: String, role: SpeakerRole, origin: Date, keywords: [String],
         onEvent: @escaping OpenAITranscriber.EventHandler, onError: @escaping OpenAITranscriber.ErrorHandler) {
        self.origin = origin; self.onError = onError
        transcriber = OpenAITranscriber(key: key, role: role, origin: origin, keywords: keywords, onEvent: onEvent, onError: onError)
    }
    func prepare() async throws { try await transcriber.start() }
    func consume(_ buffer: AVAudioPCMBuffer, capturedAt: Date) async {
        guard !failed else { return }
        do {
            let pcm = try convert(buffer)
            let start = max(0, capturedAt.timeIntervalSince(origin) - Double(pcm.count) / 48000)
            if let turn = vad.ingest(pcm, startSeconds: start) { try await transcriber.submit(turn) }
        } catch {
            failed = true
            onError((error as? OpenAIError)?.localizedDescription ?? "Audio conversion or upload failed; capture stopped.")
        }
    }
    func stop() async {
        if !failed, let turn = vad.flush() { try? await transcriber.submit(turn) }
        await transcriber.finish()
    }
    private func convert(_ input: AVAudioPCMBuffer) throws -> Data {
        if input.format != inputFormat {
            converter = AVAudioConverter(from: input.format, to: target); inputFormat = input.format
        }
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: target,
                  frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * 24000 / input.format.sampleRate) + 64)) else {
            throw OpenAIError.invalidResponse
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard !supplied else { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        guard error == nil, status != .error else { throw OpenAIError.invalidResponse }
        guard output.frameLength > 0, let bytes = output.int16ChannelData?[0] else { return Data() }
        return Data(bytes: bytes, count: Int(output.frameLength) * 2)
    }
}
