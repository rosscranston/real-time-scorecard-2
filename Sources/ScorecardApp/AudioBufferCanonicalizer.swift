import AVFoundation
import CoreMedia
import Foundation

// PCM conversion adapted from the prior Live Scorecard app.
enum AudioBufferConversionError: Error, LocalizedError {
    case missingFormatDescription
    case unsupportedFormat(String)
    case emptyBuffer
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFormatDescription:
            return "the sample has no Core Audio format description"
        case let .unsupportedFormat(format):
            return "unsupported PCM format (\(format))"
        case .emptyBuffer:
            return "the sample contains no audio frames"
        case let .conversionFailed(reason):
            return "PCM conversion failed (\(reason))"
        }
    }
}

enum AudioBufferCanonicalizer {
    static func makeCanonicalMonoBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = sampleBuffer.formatDescription else {
            throw AudioBufferConversionError.missingFormatDescription
        }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        var result: AVAudioPCMBuffer?
        try sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let borrowed = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                bufferListNoCopy: audioBufferList.unsafePointer
            ) else {
                throw AudioBufferConversionError.unsupportedFormat(formatSummary(sourceFormat))
            }
            result = try makeCanonicalMonoBuffer(from: borrowed)
        }
        guard let result else { throw AudioBufferConversionError.emptyBuffer }
        return result
    }

    static func makeCanonicalMonoBuffer(from input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard input.frameLength > 0 else { throw AudioBufferConversionError.emptyBuffer }
        guard let floatFormat = AVAudioFormat(
            standardFormatWithSampleRate: input.format.sampleRate,
            channels: input.format.channelCount
        ) else {
            throw AudioBufferConversionError.unsupportedFormat(formatSummary(input.format))
        }

        let floatBuffer = try convertedCopy(input, to: floatFormat)
        guard let channels = floatBuffer.floatChannelData,
              let monoFormat = AVAudioFormat(
                standardFormatWithSampleRate: floatBuffer.format.sampleRate,
                channels: 1
              ),
              let monoBuffer = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: floatBuffer.frameLength
              ),
              let monoSamples = monoBuffer.floatChannelData?[0]
        else { throw AudioBufferConversionError.unsupportedFormat(formatSummary(floatBuffer.format)) }

        let frameCount = Int(floatBuffer.frameLength)
        let channelCount = Int(floatBuffer.format.channelCount)
        var loudestChannel = 0
        var loudestEnergy = -Double.infinity
        for channel in 0..<channelCount {
            var energy = 0.0
            for frame in 0..<frameCount {
                let sample = Double(channels[channel][frame])
                energy += sample * sample
            }
            if energy > loudestEnergy {
                loudestEnergy = energy
                loudestChannel = channel
            }
        }

        monoBuffer.frameLength = floatBuffer.frameLength
        memcpy(
            monoSamples,
            channels[loudestChannel],
            frameCount * MemoryLayout<Float>.size
        )
        return monoBuffer
    }

    static func formatSummary(_ format: AVAudioFormat) -> String {
        let commonFormat: String
        switch format.commonFormat {
        case .pcmFormatFloat32: commonFormat = "float32"
        case .pcmFormatFloat64: commonFormat = "float64"
        case .pcmFormatInt16: commonFormat = "int16"
        case .pcmFormatInt32: commonFormat = "int32"
        case .otherFormat: commonFormat = "other"
        @unknown default: commonFormat = "unknown"
        }
        return "\(Int(format.sampleRate)) Hz / \(format.channelCount) ch / \(commonFormat) / \(format.isInterleaved ? "interleaved" : "planar")"
    }

    private static func convertedCopy(
        _ input: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: input.format, to: outputFormat) else {
            throw AudioBufferConversionError.conversionFailed(
                "no converter from \(formatSummary(input.format)) to \(formatSummary(outputFormat))"
            )
        }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up) + 16)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioBufferConversionError.conversionFailed("could not allocate output buffer")
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if let conversionError {
            throw AudioBufferConversionError.conversionFailed(conversionError.localizedDescription)
        }
        guard status == .haveData || status == .inputRanDry || status == .endOfStream,
              output.frameLength > 0 else {
            throw AudioBufferConversionError.conversionFailed("status \(status.rawValue), zero output frames")
        }
        return output
    }
}

enum AudioLevelMeter {
    static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        normalizedLevel(rms: rms(from: buffer))
    }

    static func rms(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0,
              buffer.format.channelCount > 0 else { return 0 }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sumOfSquares = 0.0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                let sample = Double(samples[frame])
                sumOfSquares += sample * sample
            }
            sampleCount += frameCount
        }

        guard sampleCount > 0 else { return 0 }
        return sqrt(sumOfSquares / Double(sampleCount))
    }

    static func normalizedLevel(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(1, max(0, (decibels + 60) / 60))
    }
}
