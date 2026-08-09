import Foundation

@main
struct VoiceLibrarySelfTest {
    @MainActor
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let testRoot = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"],
              let support = environment["LOCAL_AUDIO_PROBE_APP_SUPPORT"],
              let output = environment["LOCAL_AUDIO_PROBE_OUTPUT_DIR"],
              support.hasPrefix(testRoot),
              output.hasPrefix(testRoot) else {
            throw SelfTestError.invalidTestDirectories
        }

        let firstLibrary = VoiceLibrary()
        try require(firstLibrary.profiles.count == 1, "首次载入应只有内置音色")

        let created = try firstLibrary.createVoice(
            name: "自动测试音色",
            referenceText: ProbeConfiguration.defaultReferenceText,
            sourceAudioURL: ProbeConfiguration.defaultReferenceAudio
        )
        try require(!created.isBuiltIn, "新建音色不应标记为内置")
        try require(
            FileManager.default.fileExists(atPath: created.referenceAudioPath),
            "降噪参考音频不存在"
        )
        try require(created.referenceAudioPath.hasSuffix("reference-clean.wav"), "合成应使用降噪参考音频")
        try require(created.processedAudioPath == created.referenceAudioPath, "处理音频路径不一致")
        guard let originalAudioPath = created.originalAudioPath else {
            throw SelfTestError.failed("没有记录原始参考音频路径")
        }
        try require(
            FileManager.default.fileExists(atPath: originalAudioPath),
            "原始参考音频没有保留"
        )
        try require(created.qualitySummary != nil, "没有保存参考音频质量信息")
        try require(firstLibrary.selectedVoiceID == created.id, "新音色应自动选中")

        let secondLibrary = VoiceLibrary()
        try require(secondLibrary.profiles.count == 2, "重新载入后应保留自定义音色")
        try require(secondLibrary.selectedProfile.id == created.id, "重新载入后应恢复选择")

        let info = try audioInfo(for: created.referenceAudioURL)
        try require(info.contains("1 ch"), "参考音频应为单声道")
        try require(info.contains("24000 Hz"), "参考音频应为 24kHz")
        let cleanQuality = try AudioProcessor.analyzePCM16WAV(at: created.referenceAudioURL)
        try require(cleanQuality.peakDBFS <= -0.95, "降噪参考音频峰值过高")

        let processedOutput = URL(fileURLWithPath: output)
            .appendingPathComponent("post-process-self-test.wav")
        try AudioProcessor.postProcessOutput(
            from: created.referenceAudioURL,
            to: processedOutput
        )
        let outputQuality = try AudioProcessor.analyzePCM16WAV(at: processedOutput)
        try require(outputQuality.peakDBFS <= -0.95, "后处理结果超过安全峰值")
        try require(
            FileManager.default.fileExists(atPath: ProbeConfiguration.voicesIndexURL.path),
            "音色索引未写入"
        )
        try require(
            FileManager.default.fileExists(atPath: ProbeConfiguration.outputDirectory.path),
            "输出目录未创建"
        )

        let originalURL = URL(fileURLWithPath: originalAudioPath)
        let cleanRecording = VoiceProfile(
            id: "clean-reference",
            name: "干净录音",
            referenceAudioPath: created.referenceAudioPath,
            originalAudioPath: originalAudioPath,
            processedAudioPath: created.referenceAudioPath,
            qualitySummary: AudioQualitySummary(
                duration: 15,
                peakDBFS: -3,
                rmsDBFS: -20,
                noiseFloorDBFS: -55,
                clippingFraction: 0
            ),
            referenceText: "参考原文",
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        try require(
            cleanRecording.synthesisReferenceAudioURL == originalURL,
            "干净录音应保留原声细节"
        )

        let noisyRecording = VoiceProfile(
            id: "noisy-reference",
            name: "有底噪录音",
            referenceAudioPath: created.referenceAudioPath,
            originalAudioPath: originalAudioPath,
            processedAudioPath: created.referenceAudioPath,
            qualitySummary: AudioQualitySummary(
                duration: 15,
                peakDBFS: -3,
                rmsDBFS: -20,
                noiseFloorDBFS: -35,
                clippingFraction: 0
            ),
            referenceText: "参考原文",
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        try require(
            noisyRecording.synthesisReferenceAudioURL == created.referenceAudioURL,
            "有明显底噪时应使用清理版参考音频"
        )

        let missingOriginalRecording = VoiceProfile(
            id: cleanRecording.id,
            name: cleanRecording.name,
            referenceAudioPath: cleanRecording.referenceAudioPath,
            originalAudioPath: URL(fileURLWithPath: support)
                .appendingPathComponent("missing-original.wav").path,
            processedAudioPath: cleanRecording.processedAudioPath,
            qualitySummary: cleanRecording.qualitySummary,
            referenceText: cleanRecording.referenceText,
            createdAt: cleanRecording.createdAt,
            authorizationConfirmedAt: cleanRecording.authorizationConfirmedAt,
            isBuiltIn: cleanRecording.isBuiltIn
        )
        try require(
            missingOriginalRecording.synthesisReferenceAudioURL == created.referenceAudioURL,
            "原始录音丢失时应自动回退到现有清理版"
        )

        print("VoiceLibrarySelfTest PASS")
        print("profile=\(created.id)")
        print("audio=\(created.referenceAudioPath)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SelfTestError.failed(message) }
    }

    private static func audioInfo(for url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afinfo")
        process.arguments = [url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            throw SelfTestError.failed("afinfo 无法读取标准化音频")
        }
        return text
    }
}

enum SelfTestError: LocalizedError {
    case invalidTestDirectories
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTestDirectories:
            return "自检必须使用独立临时目录"
        case .failed(let message):
            return message
        }
    }
}
