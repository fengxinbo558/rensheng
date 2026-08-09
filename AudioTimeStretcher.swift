import AVFoundation
import Foundation

struct AudioTimeStretchResult {
    let outputURL: URL
    let rate: Double
    let durationSeconds: TimeInterval
    let sampleRate: Double
}

final class AudioTimeStretcher {
    private let maximumFrameCount: AVAudioFrameCount = 4_096

    func stretch(input: URL, output: URL, rate requestedRate: Double) throws -> AudioTimeStretchResult {
        let rate = NarrationSegment.normalizedSpeedFactor(requestedRate)
        let inputFile = try AVAudioFile(forReading: input)
        let inputFormat = inputFile.processingFormat
        guard inputFile.length > 0,
              inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0 else {
            throw AudioTimeStretcherError.emptyInput
        }

        let renderFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        )!
        let expectedFrames = max(
            AVAudioFramePosition(1),
            AVAudioFramePosition((Double(inputFile.length) / rate).rounded())
        )

        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString).time-stretch.tmp.wav")
        defer { try? FileManager.default.removeItem(at: temporary) }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(rate)
        timePitch.pitch = 0
        timePitch.overlap = rate < 0.6 || rate > 2.0 ? 24 : 12

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: inputFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: renderFormat)
        try engine.enableManualRenderingMode(
            .offline,
            format: renderFormat,
            maximumFrameCount: maximumFrameCount
        )

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: renderFormat.sampleRate,
            AVNumberOfChannelsKey: Int(renderFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outputFile = try AVAudioFile(
            forWriting: temporary,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maximumFrameCount
        ) else {
            throw AudioTimeStretcherError.bufferCreationFailed
        }

        player.scheduleFile(inputFile, at: nil)
        try engine.start()
        player.play()
        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        var writtenFrames: AVAudioFramePosition = 0
        var attemptsWithoutData = 0
        while writtenFrames < expectedFrames {
            let remaining = expectedFrames - writtenFrames
            let requestedFrames = AVAudioFrameCount(
                min(AVAudioFramePosition(maximumFrameCount), remaining)
            )
            let status = try engine.renderOffline(requestedFrames, to: buffer)
            switch status {
            case .success:
                guard buffer.frameLength > 0 else {
                    attemptsWithoutData += 1
                    if attemptsWithoutData > 100 {
                        throw AudioTimeStretcherError.renderingStalled
                    }
                    continue
                }
                attemptsWithoutData = 0
                if AVAudioFramePosition(buffer.frameLength) > remaining {
                    buffer.frameLength = AVAudioFrameCount(remaining)
                }
                try outputFile.write(from: buffer)
                writtenFrames += AVAudioFramePosition(buffer.frameLength)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                attemptsWithoutData += 1
                if attemptsWithoutData > 100 {
                    throw AudioTimeStretcherError.renderingStalled
                }
            case .error:
                throw AudioTimeStretcherError.renderingFailed
            @unknown default:
                throw AudioTimeStretcherError.renderingFailed
            }
        }

        guard writtenFrames == expectedFrames else {
            throw AudioTimeStretcherError.invalidOutput
        }
        if FileManager.default.fileExists(atPath: output.path) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: output)
        }
        return AudioTimeStretchResult(
            outputURL: output,
            rate: rate,
            durationSeconds: Double(expectedFrames) / renderFormat.sampleRate,
            sampleRate: renderFormat.sampleRate
        )
    }
}

enum AudioTimeStretcherError: LocalizedError {
    case emptyInput
    case bufferCreationFailed
    case renderingStalled
    case renderingFailed
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "需要变速的音频没有有效内容"
        case .bufferCreationFailed:
            return "无法准备本地变速缓冲区"
        case .renderingStalled:
            return "本地变速处理没有继续输出声音"
        case .renderingFailed:
            return "本地保持音高变速失败"
        case .invalidOutput:
            return "变速后的音频没有通过完整性检查"
        }
    }
}
