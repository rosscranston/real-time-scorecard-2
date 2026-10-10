@preconcurrency import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Foundation
import ScorecardCore

private struct OwnedAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let capturedAt: Date
}

final class LiveAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let onError: @Sendable (String) -> Void
    private let mic: any AudioChannel
    private let meeting: any AudioChannel
    private let queue = DispatchQueue(label: "ai.cranston.scorecard2.capture")
    private var stream: SCStream?
    private let micInput: AsyncStream<OwnedAudioBuffer>.Continuation
    private let meetingInput: AsyncStream<OwnedAudioBuffer>.Continuation
    private var consumers: [Task<Void, Never>] = []
    private let lock = NSLock()
    private var accepting = true
    private var reportedDrop = false

    init(microphone: any AudioChannel, meeting: any AudioChannel, onError: @escaping @Sendable (String) -> Void) {
        self.mic = microphone; self.meeting = meeting; self.onError = onError
        let (micStream, micInput) = AsyncStream.makeStream(of: OwnedAudioBuffer.self, bufferingPolicy: .bufferingOldest(200))
        let (meetingStream, meetingInput) = AsyncStream.makeStream(of: OwnedAudioBuffer.self, bufferingPolicy: .bufferingOldest(200))
        self.micInput = micInput; self.meetingInput = meetingInput
        super.init()
        consumers = [
            Task { for await frame in micStream { await microphone.consume(frame.buffer, capturedAt: frame.capturedAt) } },
            Task { for await frame in meetingStream { await meeting.consume(frame.buffer, capturedAt: frame.capturedAt) } }
        ]
    }
    func start(browserBundleID: String, microphoneID: String?) async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw DatabaseError(message: "Allow Microphone access in System Settings to capture your side of the call.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first else { throw DatabaseError(message: "No display is available for meeting audio capture.") }
        let apps = content.applications.filter { $0.bundleIdentifier == browserBundleID }
        guard !apps.isEmpty else { throw DatabaseError(message: "Open your selected meeting browser before starting audio.") }
        // Restrict capture to the selected browser. Never silently capture every app.
        let filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2; config.queueDepth = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000; config.channelCount = 2
        config.captureMicrophone = true; config.microphoneCaptureDeviceID = microphoneID
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        self.stream = stream
        // Use the completion API; the old app found the async importer could hang.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
    func stop() async {
        lock.withLock { accepting = false }
        if let stream { try? await stream.stopCapture() }
        stream = nil
        micInput.finish(); meetingInput.finish()
        for consumer in consumers { await consumer.value }
        consumers.removeAll()
        async let stopMic: Void = mic.stop()
        async let stopMeeting: Void = meeting.stop()
        _ = await (stopMic, stopMeeting)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError("Meeting audio capture stopped. Check Screen & System Audio Recording permission, then reconnect.")
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard lock.withLock({ accepting }), [.audio, .microphone].contains(outputType), sampleBuffer.isValid else { return }
        do {
            let capturedAt = Date()
            let owned = OwnedAudioBuffer(buffer: try AudioBufferCanonicalizer.makeCanonicalMonoBuffer(from: sampleBuffer), capturedAt: capturedAt)
            let result = (outputType == .microphone ? micInput : meetingInput).yield(owned)
            if case .dropped = result, !reportedDrop {
                reportedDrop = true
                onError("Audio input fell behind; some audio is missing. Capture paused; reconnect to continue.")
            }
        } catch {
            if !reportedDrop { reportedDrop = true; onError("A captured audio buffer could not be decoded. Capture paused.") }
        }
    }
}
