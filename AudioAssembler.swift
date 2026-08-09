import Foundation

struct AudioAssemblyResult {
    let outputURL: URL
    let segmentCount: Int
    let durationSeconds: TimeInterval
    let sampleRate: Double
}

final class AudioAssembler {
    private let store: ProjectStore
    private let sampleRate = 48_000.0

    init(store: ProjectStore) {
        self.store = store
    }

    func assemble(
        project: NarrationProject,
        destination: URL
    ) throws -> AudioAssemblyResult {
        let segments = project.segments.sorted { $0.order < $1.order }
        guard !segments.isEmpty else { throw AudioAssemblerError.noSegments }

        var combined: [Double] = []
        for (position, segment) in segments.enumerated() {
            guard segment.generationState == .completed,
                  let selectedID = segment.selectedCandidateID,
                  let candidate = segment.candidates.first(where: { $0.id == selectedID }),
                  candidate.inputFingerprint == segment.inputFingerprint else {
                throw AudioAssemblerError.segmentNotReady(position + 1)
            }
            let input = try store.resolveProjectFileURL(
                projectID: project.id,
                relativePath: candidate.relativePath
            )
            guard FileManager.default.fileExists(atPath: input.path) else {
                throw AudioAssemblerError.missingSegment(position + 1)
            }

            let wave = try AudioProcessor.readPCM16WAV(at: input)
            var samples = resample(
                wave.samples,
                from: wave.sampleRate,
                to: sampleRate
            )
            guard !samples.isEmpty else { throw AudioAssemblerError.emptySegment(position + 1) }
            normalize(&samples)
            applyFades(&samples, milliseconds: 10)
            combined.append(contentsOf: samples)

            if position < segments.count - 1 {
                combined.append(
                    contentsOf: repeatElement(
                        0.0,
                        count: Int((pauseSeconds(segment.pause) * sampleRate).rounded())
                    )
                )
            }
        }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try AudioProcessor.writePCM16WAV(
            PCM16Wave(sampleRate: sampleRate, samples: combined),
            to: destination
        )
        let quality = try AudioProcessor.analyzePCM16WAV(at: destination)
        guard quality.duration > 0, quality.clippingFraction < 0.0001 else {
            throw AudioAssemblerError.invalidOutput
        }
        return AudioAssemblyResult(
            outputURL: destination,
            segmentCount: segments.count,
            durationSeconds: quality.duration,
            sampleRate: sampleRate
        )
    }

    private func resample(_ samples: [Double], from sourceRate: Double, to targetRate: Double) -> [Double] {
        guard !samples.isEmpty, sourceRate > 0, targetRate > 0 else { return [] }
        if abs(sourceRate - targetRate) < 0.5 { return samples }
        let outputCount = max(1, Int((Double(samples.count) * targetRate / sourceRate).rounded()))
        if outputCount == 1 { return [samples[0]] }
        let scale = sourceRate / targetRate
        return (0..<outputCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) * scale
            let lower = min(samples.count - 1, Int(sourcePosition))
            let upper = min(samples.count - 1, lower + 1)
            let fraction = sourcePosition - Double(lower)
            return samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
    }

    private func normalize(_ samples: inout [Double]) {
        guard !samples.isEmpty else { return }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
        let peak = samples.lazy.map(abs).max() ?? 0
        guard rms > 0, peak > 0 else { return }
        let targetRMS = pow(10.0, -22.0 / 20.0)
        let safePeak = pow(10.0, -1.0 / 20.0)
        let gain = min(max(targetRMS / rms, 0.5), 2.0, safePeak / peak)
        for index in samples.indices { samples[index] *= gain }
    }

    private func applyFades(_ samples: inout [Double], milliseconds: Double) {
        let count = min(
            samples.count / 2,
            max(1, Int(sampleRate * milliseconds / 1_000))
        )
        guard count > 1 else { return }
        for index in 0..<count {
            let gain = Double(index) / Double(count - 1)
            samples[index] *= gain
            samples[samples.count - 1 - index] *= gain
        }
    }

    private func pauseSeconds(_ pause: NarrationPause) -> Double {
        switch pause {
        case .short: return 0.25
        case .normal: return 0.55
        case .long: return 0.9
        }
    }
}

enum AudioAssemblerError: LocalizedError {
    case noSegments
    case segmentNotReady(Int)
    case missingSegment(Int)
    case emptySegment(Int)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "项目里还没有可拼接的段落"
        case .segmentNotReady(let number):
            return "第 \(number) 段还没有生成完成"
        case .missingSegment(let number):
            return "第 \(number) 段的本地音频丢失"
        case .emptySegment(let number):
            return "第 \(number) 段没有有效声音"
        case .invalidOutput:
            return "成品音频没有通过完整性检查"
        }
    }
}
