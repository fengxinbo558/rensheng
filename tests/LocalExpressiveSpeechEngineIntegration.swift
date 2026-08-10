import Foundation

private enum ExpressiveIntegrationFailure: Error {
    case missingEnvironment(String)
    case assertion(String)
}

@main
struct LocalExpressiveSpeechEngineIntegration {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let referencePath = environment["LOCAL_AUDIO_TEST_REFERENCE_AUDIO"] else {
            throw ExpressiveIntegrationFailure.missingEnvironment("缺少参考录音")
        }
        guard let referenceText = environment["LOCAL_AUDIO_TEST_REFERENCE_TEXT"] else {
            throw ExpressiveIntegrationFailure.missingEnvironment("缺少参考原文")
        }
        guard let outputPath = environment["LOCAL_AUDIO_TEST_OUTPUT"] else {
            throw ExpressiveIntegrationFailure.missingEnvironment("缺少输出路径")
        }
        let referenceURL = URL(fileURLWithPath: referencePath)
        let outputURL = URL(fileURLWithPath: outputPath)
        let voice = VoiceProfile(
            id: "expressive-integration",
            name: "集成验证音色",
            referenceAudioPath: referenceURL.path,
            originalAudioPath: nil,
            processedAudioPath: nil,
            qualitySummary: nil,
            referenceText: referenceText,
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        let engine = LocalExpressiveSpeechEngine()
        guard engine.isAvailable else {
            throw ExpressiveIntegrationFailure.assertion(
                engine.unavailableReason ?? "情绪引擎不可用"
            )
        }
        let result = try engine.synthesize(
            request: SpeechSynthesisRequest(
                text: "这个结果挺好的，我想用很平常的语气和你分享。",
                voice: voice,
                outputURL: outputURL,
                zipVoiceSteps: 8,
                expression: .happy,
                expressionIntensity: .subtle
            )
        ) { _ in }
        let quality = try AudioProcessor.analyzeAudio(at: result.outputURL)
        guard quality.duration > 1, quality.clippingFraction < 0.0001 else {
            throw ExpressiveIntegrationFailure.assertion("生成音频没有通过质量检查")
        }
        print(
            String(
                format: "LocalExpressiveSpeechEngineIntegration: PASS duration=%.2f peak=%.1f dBFS",
                quality.duration,
                quality.peakDBFS
            )
        )
    }
}
