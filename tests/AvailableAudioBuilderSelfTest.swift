import Foundation

private enum AvailableAudioTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func availableExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw AvailableAudioTestFailure.assertion(message) }
}

@main
struct AvailableAudioBuilderSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw AvailableAudioTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        let store = ProjectStore(rootDirectory: root)
        var project = try store.createProject(
            name: "可用音频测试",
            sourceText: "第一段。第二段。第三段。",
            voiceID: "voice-a"
        )
        project.segments = (0..<3).map { index in
            NarrationSegment(
                order: index,
                text: "第 \(index + 1) 段。",
                kind: .explanation,
                voiceID: project.voiceID
            )
        }

        for index in [0, 2] {
            let relativePath = "segments/segment-\(index).wav"
            let audioURL = try store.resolveProjectFileURL(
                projectID: project.id,
                relativePath: relativePath
            )
            try AudioProcessor.writePCM16WAV(
                PCM16Wave(
                    sampleRate: 48_000,
                    samples: (0..<9_600).map {
                        sin(2 * Double.pi * Double(330 + index * 40) * Double($0) / 48_000) * 0.08
                    }
                ),
                to: audioURL
            )
            let candidate = NarrationAudioCandidate(
                relativePath: relativePath,
                inputFingerprint: project.segments[index].inputFingerprint,
                engineName: "测试",
                durationSeconds: 0.2
            )
            project.segments[index].candidates = [candidate]
            project.segments[index].selectedCandidateID = candidate.id
            project.segments[index].generationState = .completed
        }
        try store.save(project)

        let builder = AvailableAudioBuilder(store: store)
        try availableExpect(builder.availableSegmentCount(in: project) == 1, "不应越过未完成的第二段")
        let firstPreview = try builder.build(project: project)
        try availableExpect(firstPreview.segmentCount == 1, "首段预览段数不正确")
        try availableExpect(FileManager.default.fileExists(atPath: firstPreview.outputURL.path), "首段预览没有生成")

        let secondRelativePath = "segments/segment-1.wav"
        let secondURL = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: secondRelativePath
        )
        try AudioProcessor.writePCM16WAV(
            PCM16Wave(sampleRate: 48_000, samples: Array(repeating: 0.03, count: 9_600)),
            to: secondURL
        )
        let secondCandidate = NarrationAudioCandidate(
            relativePath: secondRelativePath,
            inputFingerprint: project.segments[1].inputFingerprint,
            engineName: "测试",
            durationSeconds: 0.2
        )
        project.segments[1].candidates = [secondCandidate]
        project.segments[1].selectedCandidateID = secondCandidate.id
        project.segments[1].generationState = .completed
        try availableExpect(builder.availableSegmentCount(in: project) == 3, "连续完成后应包含三段")
        let fullPreview = try builder.build(project: project)
        try availableExpect(fullPreview.segmentCount == 3, "刷新后的预览段数不正确")

        print("AvailableAudioBuilderSelfTest: PASS")
    }
}
