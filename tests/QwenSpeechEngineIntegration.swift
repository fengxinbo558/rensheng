import Foundation

private enum IntegrationError: Error, CustomStringConvertible {
    case missingEnvironment(String)

    var description: String {
        switch self {
        case .missingEnvironment(let name): return "缺少环境变量：\(name)"
        }
    }
}

@main
struct QwenSpeechEngineIntegration {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let referencePath = environment["LOCAL_AUDIO_QWEN_INTEGRATION_REFERENCE"] else {
            throw IntegrationError.missingEnvironment("LOCAL_AUDIO_QWEN_INTEGRATION_REFERENCE")
        }
        guard let referenceText = environment["LOCAL_AUDIO_QWEN_INTEGRATION_REFERENCE_TEXT"] else {
            throw IntegrationError.missingEnvironment("LOCAL_AUDIO_QWEN_INTEGRATION_REFERENCE_TEXT")
        }
        guard let outputPath = environment["LOCAL_AUDIO_QWEN_INTEGRATION_OUTPUT"] else {
            throw IntegrationError.missingEnvironment("LOCAL_AUDIO_QWEN_INTEGRATION_OUTPUT")
        }

        let voice = VoiceProfile(
            id: "integration-voice",
            name: "真实链路测试音色",
            referenceAudioPath: referencePath,
            originalAudioPath: referencePath,
            processedAudioPath: nil,
            qualitySummary: nil,
            referenceText: referenceText,
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        let output = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: output)

        let preCancelledEngine = QwenSpeechEngine()
        preCancelledEngine.cancel()
        do {
            _ = try preCancelledEngine.synthesize(
                request: SpeechSynthesisRequest(
                    text: "这段文字不应生成。",
                    voice: voice,
                    outputURL: output.deletingLastPathComponent()
                        .appendingPathComponent("cancelled-before-start.wav"),
                    zipVoiceSteps: 8
                )
            ) { _ in }
            throw SpeechEngineError.generationFailed("开始前取消没有生效")
        } catch SpeechEngineError.cancelled {
            print("cancel-before-start=PASS")
        }

        let engine = QwenSpeechEngine()
        guard engine.isAvailable else {
            throw SpeechEngineError.unavailable(engine.unavailableReason ?? "未知资源")
        }
        let started = Date()
        let result = try engine.synthesize(
            request: SpeechSynthesisRequest(
                text: "这是一段自然人声桌面应用的真实链路测试。",
                voice: voice,
                outputURL: output,
                zipVoiceSteps: 8
            )
        ) { progress in
            print("progress=\(progress.statusLabel)")
        }
        guard FileManager.default.fileExists(atPath: result.outputURL.path) else {
            throw SpeechEngineError.missingOutput
        }
        print("output=\(result.outputURL.path)")
        print(String(format: "elapsed=%.3f", Date().timeIntervalSince(started)))
        print("QwenSpeechEngineIntegration: PASS")
    }
}
