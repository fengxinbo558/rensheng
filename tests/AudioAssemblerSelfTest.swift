import Foundation

private enum AudioAssemblerTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func audioExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw AudioAssemblerTestFailure.assertion(message) }
}

@main
struct AudioAssemblerSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw AudioAssemblerTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("AudioProjects", isDirectory: true)
        let store = ProjectStore(rootDirectory: root)
        var project = try store.createProject(
            name: "拼接测试",
            sourceText: "第一段。第二段。",
            voiceID: "voice-a"
        )
        project.segments = [
            NarrationSegment(
                order: 0,
                text: "第一段。",
                kind: .explanation,
                speedFactor: 0.5,
                pause: .short,
                voiceID: project.voiceID
            ),
            NarrationSegment(
                order: 1,
                text: "第二段。",
                kind: .conclusion,
                speedFactor: 2.0,
                pause: .long,
                voiceID: project.voiceID
            ),
        ]

        let firstRelative = "segments/first.wav"
        let secondRelative = "segments/second.wav"
        let firstURL = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: firstRelative
        )
        let secondURL = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: secondRelative
        )
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try AudioProcessor.writePCM16WAV(
            PCM16Wave(
                sampleRate: 24_000,
                samples: (0..<12_000).map { sin(2 * Double.pi * 330 * Double($0) / 24_000) * 0.08 }
            ),
            to: firstURL
        )
        try AudioProcessor.writePCM16WAV(
            PCM16Wave(
                sampleRate: 48_000,
                samples: (0..<19_200).map { sin(2 * Double.pi * 440 * Double($0) / 48_000) * 0.16 }
            ),
            to: secondURL
        )

        let firstCandidate = NarrationAudioCandidate(
            relativePath: firstRelative,
            inputFingerprint: project.segments[0].inputFingerprint,
            engineName: "测试",
            durationSeconds: 0.5
        )
        let secondCandidate = NarrationAudioCandidate(
            relativePath: secondRelative,
            inputFingerprint: project.segments[1].inputFingerprint,
            engineName: "测试",
            durationSeconds: 0.4
        )
        project.segments[0].candidates = [firstCandidate]
        project.segments[0].selectedCandidateID = firstCandidate.id
        project.segments[0].generationState = .completed
        project.segments[1].candidates = [secondCandidate]
        project.segments[1].selectedCandidateID = secondCandidate.id
        project.segments[1].generationState = .completed
        try store.save(project)

        let master = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: "final/master.wav"
        )
        let result = try AudioAssembler(store: store).assemble(
            project: project,
            destination: master
        )
        try audioExpect(result.segmentCount == 2, "成品段落数不正确")
        try audioExpect(abs(result.durationSeconds - 1.45) < 0.04, "逐段变速、拼接时长或短停顿不正确：\(result.durationSeconds)")
        let masterQuality = try AudioProcessor.analyzePCM16WAV(at: master)
        try audioExpect(masterQuality.clippingFraction == 0, "拼接结果出现削波")
        try audioExpect(masterQuality.peakDBFS <= -0.9, "拼接结果峰值不安全")
        try audioExpect(FileManager.default.fileExists(atPath: firstURL.path), "拼接不应删除第一段母版")
        try audioExpect(FileManager.default.fileExists(atPath: secondURL.path), "拼接不应删除第二段母版")

        let exporter = AudioExporter()
        let m4a = master.deletingPathExtension().appendingPathExtension("m4a")
        let mp3 = master.deletingPathExtension().appendingPathExtension("mp3")
        try exporter.export(wav: master, to: m4a, format: .m4a)
        try exporter.export(wav: master, to: mp3, format: .mp3)
        let m4aQuality = try AudioProcessor.analyzeAudio(at: m4a)
        let mp3Quality = try AudioProcessor.analyzeAudio(at: mp3)
        try audioExpect(m4aQuality.duration > 1.4, "M4A 无法独立读取")
        try audioExpect(mp3Quality.duration > 1.4, "MP3 无法独立读取")

        print("AudioAssemblerSelfTest: PASS")
        print("wav=\(master.path)")
        print("m4a=\(m4a.path)")
        print("mp3=\(mp3.path)")
    }
}
