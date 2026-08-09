import Foundation

private enum AudioTimeStretcherTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func stretchExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw AudioTimeStretcherTestFailure.assertion(message) }
}

private func estimatedFrequency(_ samples: [Double], sampleRate: Double) -> Double {
    guard samples.count > 4 else { return 0 }
    let start = samples.count / 4
    let end = samples.count * 3 / 4
    var crossings = 0
    for index in (start + 1)..<end where samples[index - 1] <= 0 && samples[index] > 0 {
        crossings += 1
    }
    let duration = Double(end - start) / sampleRate
    return duration > 0 ? Double(crossings) / duration : 0
}

@main
struct AudioTimeStretcherSelfTest {
    static func main() throws {
        guard let rootPath = ProcessInfo.processInfo.environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw AudioTimeStretcherTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let input = root.appendingPathComponent("tone.wav")
        let sampleRate = 48_000.0
        let samples = (0..<Int(sampleRate)).map { index in
            sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.25
        }
        try AudioProcessor.writePCM16WAV(
            PCM16Wave(sampleRate: sampleRate, samples: samples),
            to: input
        )

        let stretcher = AudioTimeStretcher()
        for (rate, expectedDuration) in [(0.5, 2.0), (2.0, 0.5)] {
            let output = root.appendingPathComponent("tone-\(rate).wav")
            let result = try stretcher.stretch(input: input, output: output, rate: rate)
            let wave = try AudioProcessor.readPCM16WAV(at: output)
            let duration = Double(wave.samples.count) / wave.sampleRate
            let frequency = estimatedFrequency(wave.samples, sampleRate: wave.sampleRate)
            try stretchExpect(abs(result.rate - rate) < 0.001, "变速档位不正确")
            try stretchExpect(abs(duration - expectedDuration) < 0.03, "\(rate)倍输出时长不正确：\(duration)")
            try stretchExpect((410...470).contains(frequency), "\(rate)倍输出没有保持音高：\(frequency)Hz")
        }

        for (rate, expectedDuration) in [(0.1, 10.0), (3.0, 1.0 / 3.0)] {
            let output = root.appendingPathComponent("tone-limit-\(rate).wav")
            _ = try stretcher.stretch(input: input, output: output, rate: rate)
            let quality = try AudioProcessor.analyzePCM16WAV(at: output)
            try stretchExpect(
                abs(quality.duration - expectedDuration) < 0.04,
                "边界速度 \(rate) 倍输出时长不正确：\(quality.duration)"
            )
        }

        print("AudioTimeStretcherSelfTest: PASS")
    }
}
