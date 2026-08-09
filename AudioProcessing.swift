import AVFoundation
import Foundation

enum AudioQualityLevel: String, Codable, Hashable {
    case good
    case warning
    case poor
}

struct AudioQualitySummary: Codable, Hashable {
    let duration: TimeInterval
    let peakDBFS: Double
    let rmsDBFS: Double
    let noiseFloorDBFS: Double
    let clippingFraction: Double

    var level: AudioQualityLevel {
        if clippingFraction > 0.0001 || rmsDBFS < -34 || peakDBFS < -14 {
            return .poor
        }
        if duration < 8 || noiseFloorDBFS > -45 {
            return .warning
        }
        return .good
    }

    var shortLabel: String {
        switch level {
        case .good:
            return "录音质量良好"
        case .warning:
            if duration < 8 {
                return "录音偏短，建议录制 10～30 秒"
            }
            return "检测到较明显的环境底噪，将自动降噪"
        case .poor:
            if clippingFraction > 0.0001 {
                return "录音有爆音，建议降低输入音量后重录"
            }
            return "录音音量太轻，建议靠近麦克风后重录"
        }
    }

    var detailLabel: String {
        String(
            format: "峰值 %.1f dB · 平均 %.1f dB · %.1f 秒",
            peakDBFS,
            rmsDBFS,
            duration
        )
    }
}

enum AudioProcessingError: LocalizedError {
    case unreadableAudio
    case unsupportedWAV
    case emptyAudio
    case couldNotWrite

    var errorDescription: String? {
        switch self {
        case .unreadableAudio:
            return "无法读取音频内容"
        case .unsupportedWAV:
            return "只支持单声道 16 位 PCM WAV 后处理"
        case .emptyAudio:
            return "音频中没有可处理的声音"
        case .couldNotWrite:
            return "无法写入处理后的音频"
        }
    }
}

struct PCM16Wave {
    let sampleRate: Double
    var samples: [Double]
}

enum AudioProcessor {
    static func analyzeAudio(at url: URL) throws -> AudioQualitySummary {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let capacity: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioProcessingError.unreadableAudio
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: min(capacity, AVAudioFrameCount(remaining)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            let channelCount = Int(format.channelCount)
            for frame in 0..<Int(buffer.frameLength) {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    mixed += channels[channel][frame]
                }
                samples.append(mixed / Float(max(channelCount, 1)))
            }
        }

        return qualitySummary(samples: samples.map(Double.init), sampleRate: format.sampleRate)
    }

    static func analyzePCM16WAV(at url: URL) throws -> AudioQualitySummary {
        let wave = try readPCM16WAV(at: url)
        return qualitySummary(samples: wave.samples, sampleRate: wave.sampleRate)
    }

    static func normalizeReference(from source: URL, to destination: URL) throws {
        var wave = try readPCM16WAV(at: source)
        guard !wave.samples.isEmpty else { throw AudioProcessingError.emptyAudio }

        wave.samples = highPass(wave.samples, sampleRate: wave.sampleRate, cutoff: 70)
        let rms = rootMeanSquare(wave.samples)
        let peak = wave.samples.map { abs($0) }.max() ?? 0
        guard rms > 0, peak > 0 else { throw AudioProcessingError.emptyAudio }

        let targetRMS = amplitude(db: -24)
        let targetPeak = amplitude(db: -3)
        let maximumGain = amplitude(db: 18)
        let gain = min(targetRMS / rms, targetPeak / peak, maximumGain)
        wave.samples = wave.samples.map { $0 * gain }
        applyFades(to: &wave.samples, sampleRate: wave.sampleRate, milliseconds: 12)
        try writePCM16WAV(wave, to: destination)
    }

    static func postProcessOutput(from source: URL, to destination: URL) throws {
        var wave = try readPCM16WAV(at: source)
        guard !wave.samples.isEmpty else { throw AudioProcessingError.emptyAudio }

        wave.samples = highPass(wave.samples, sampleRate: wave.sampleRate, cutoff: 55)
        removeIsolatedClicks(from: &wave.samples)
        applyQuietExpander(to: &wave.samples, sampleRate: wave.sampleRate)
        applyFades(to: &wave.samples, sampleRate: wave.sampleRate, milliseconds: 12)

        let peak = wave.samples.map { abs($0) }.max() ?? 0
        let safePeak = amplitude(db: -1)
        if peak > safePeak {
            let gain = safePeak / peak
            wave.samples = wave.samples.map { $0 * gain }
        }

        try writePCM16WAV(wave, to: destination)
    }

    private static func qualitySummary(samples: [Double], sampleRate: Double) -> AudioQualitySummary {
        guard !samples.isEmpty, sampleRate > 0 else {
            return AudioQualitySummary(
                duration: 0,
                peakDBFS: -120,
                rmsDBFS: -120,
                noiseFloorDBFS: -120,
                clippingFraction: 0
            )
        }

        let peak = samples.map { abs($0) }.max() ?? 0
        let rms = rootMeanSquare(samples)
        let clipped = Double(samples.lazy.filter { abs($0) >= 0.999 }.count) / Double(samples.count)
        let frameSize = max(1, Int(sampleRate * 0.02))
        var frameLevels: [Double] = []
        var offset = 0
        while offset + frameSize <= samples.count {
            frameLevels.append(db(rootMeanSquare(Array(samples[offset..<(offset + frameSize)]))))
            offset += frameSize
        }
        frameLevels.sort()
        let noiseIndex = frameLevels.isEmpty ? 0 : Int(Double(frameLevels.count - 1) * 0.20)
        let noiseFloor = frameLevels.isEmpty ? -120 : frameLevels[noiseIndex]

        return AudioQualitySummary(
            duration: Double(samples.count) / sampleRate,
            peakDBFS: db(peak),
            rmsDBFS: db(rms),
            noiseFloorDBFS: noiseFloor,
            clippingFraction: clipped
        )
    }

    private static func highPass(_ samples: [Double], sampleRate: Double, cutoff: Double) -> [Double] {
        guard samples.count > 1 else { return samples }
        let timeStep = 1 / sampleRate
        let resistanceCapacity = 1 / (2 * Double.pi * cutoff)
        let alpha = resistanceCapacity / (resistanceCapacity + timeStep)
        var output = Array(repeating: 0.0, count: samples.count)
        var previousInput = samples[0]
        var previousOutput = 0.0
        for index in 1..<samples.count {
            let next = alpha * (previousOutput + samples[index] - previousInput)
            output[index] = next
            previousInput = samples[index]
            previousOutput = next
        }
        return output
    }

    private static func removeIsolatedClicks(from samples: inout [Double]) {
        guard samples.count > 2 else { return }
        let original = samples
        for index in 1..<(samples.count - 1) {
            let before = original[index - 1]
            let current = original[index]
            let after = original[index + 1]
            if abs(current - before) > 0.35,
               abs(current - after) > 0.35,
               abs(before - after) < 0.10 {
                samples[index] = (before + after) / 2
            }
        }
    }

    private static func applyQuietExpander(to samples: inout [Double], sampleRate: Double) {
        let frameSize = max(1, Int(sampleRate * 0.01))
        let closeCoefficient = 1 - exp(-1 / (sampleRate * 0.040))
        let openCoefficient = 1 - exp(-1 / (sampleRate * 0.008))
        var currentGain = 1.0
        var offset = 0
        while offset < samples.count {
            let end = min(offset + frameSize, samples.count)
            let level = db(rootMeanSquare(Array(samples[offset..<end])))
            let targetGain: Double
            if level <= -55 {
                targetGain = 0.25
            } else if level >= -40 {
                targetGain = 1
            } else {
                targetGain = 0.25 + ((level + 55) / 15) * 0.75
            }

            let smoothing = targetGain < currentGain ? closeCoefficient : openCoefficient
            for index in offset..<end {
                currentGain += (targetGain - currentGain) * smoothing
                samples[index] *= currentGain
            }
            offset = end
        }
    }

    private static func applyFades(to samples: inout [Double], sampleRate: Double, milliseconds: Double) {
        let fadeCount = min(samples.count / 2, max(1, Int(sampleRate * milliseconds / 1_000)))
        guard fadeCount > 1 else { return }
        for index in 0..<fadeCount {
            let gain = Double(index) / Double(fadeCount - 1)
            samples[index] *= gain
            samples[samples.count - 1 - index] *= gain
        }
    }

    private static func rootMeanSquare(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
    }

    private static func db(_ value: Double) -> Double {
        20 * log10(max(value, 0.000001))
    }

    private static func amplitude(db: Double) -> Double {
        pow(10, db / 20)
    }

    static func readPCM16WAV(at url: URL) throws -> PCM16Wave {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              ascii(data, range: 0..<4) == "RIFF",
              ascii(data, range: 8..<12) == "WAVE" else {
            throw AudioProcessingError.unreadableAudio
        }

        var format: UInt16?
        var channels: UInt16?
        var sampleRate: UInt32?
        var bitDepth: UInt16?
        var audioBytes: Data?
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = ascii(data, range: offset..<(offset + 4))
            let chunkSize = Int(readUInt32(data, at: offset + 4))
            let start = offset + 8
            let end = start + chunkSize
            guard end <= data.count else { break }
            if chunkID == "fmt ", chunkSize >= 16 {
                format = readUInt16(data, at: start)
                channels = readUInt16(data, at: start + 2)
                sampleRate = readUInt32(data, at: start + 4)
                bitDepth = readUInt16(data, at: start + 14)
            } else if chunkID == "data" {
                audioBytes = data.subdata(in: start..<end)
            }
            offset = end + (chunkSize % 2)
        }

        guard format == 1,
              channels == 1,
              bitDepth == 16,
              let sampleRate,
              let audioBytes,
              !audioBytes.isEmpty else {
            throw AudioProcessingError.unsupportedWAV
        }

        var samples: [Double] = []
        samples.reserveCapacity(audioBytes.count / 2)
        var index = 0
        while index + 1 < audioBytes.count {
            let value = Int16(bitPattern: readUInt16(audioBytes, at: index))
            samples.append(Double(value) / 32_768)
            index += 2
        }
        return PCM16Wave(sampleRate: Double(sampleRate), samples: samples)
    }

    static func writePCM16WAV(_ wave: PCM16Wave, to url: URL) throws {
        let sampleRate = UInt32(wave.sampleRate.rounded())
        let audioByteCount = wave.samples.count * 2
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + audioByteCount), to: &data)
        data.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(sampleRate, to: &data)
        append(sampleRate * 2, to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append("data".data(using: .ascii)!)
        append(UInt32(audioByteCount), to: &data)
        for sample in wave.samples {
            let clamped = max(-1, min(1, sample))
            let integer = Int16(max(-32_768, min(32_767, Int((clamped * 32_767).rounded()))))
            append(UInt16(bitPattern: integer), to: &data)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AudioProcessingError.couldNotWrite
        }
    }

    private static func ascii(_ data: Data, range: Range<Int>) -> String {
        String(data: data.subdata(in: range), encoding: .ascii) ?? ""
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
