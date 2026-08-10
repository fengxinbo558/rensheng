import Foundation

private enum SpokenNarrationIntegrationError: Error, LocalizedError {
    case missingEnvironment(String)
    case voiceNotFound
    case incompleteGeneration

    var errorDescription: String? {
        switch self {
        case .missingEnvironment(let name): return "缺少环境变量：\(name)"
        case .voiceNotFound: return "没有找到指定的本地音色"
        case .incompleteGeneration: return "口语导演对照音频没有完整生成"
        }
    }
}

@main
struct SpokenNarrationIntegration {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let appSupportPath = environment["LOCAL_AUDIO_AB_APP_SUPPORT"] else {
            throw SpokenNarrationIntegrationError.missingEnvironment("LOCAL_AUDIO_AB_APP_SUPPORT")
        }
        guard let voiceID = environment["LOCAL_AUDIO_AB_VOICE_ID"] else {
            throw SpokenNarrationIntegrationError.missingEnvironment("LOCAL_AUDIO_AB_VOICE_ID")
        }
        guard let outputPath = environment["LOCAL_AUDIO_AB_OUTPUT_DIR"] else {
            throw SpokenNarrationIntegrationError.missingEnvironment("LOCAL_AUDIO_AB_OUTPUT_DIR")
        }
        guard let testRootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw SpokenNarrationIntegrationError.missingEnvironment("LOCAL_AUDIO_PROBE_TEST_ROOT")
        }

        let appSupport = URL(fileURLWithPath: appSupportPath, isDirectory: true)
        let voiceIndex = appSupport.appendingPathComponent("voices.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let voices = try decoder.decode([VoiceProfile].self, from: Data(contentsOf: voiceIndex))
        guard let voice = voices.first(where: { $0.id == voiceID }) else {
            throw SpokenNarrationIntegrationError.voiceNotFound
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: testRootPath, isDirectory: true)
        let sourceText = "很多人以为，本地文字转语音只是把每一个字念出来，其实真正影响听感的，常常是句子在哪里断开、哪些内容需要连着说，以及段落之间留多长的停顿。如果一口气念完，再好的音色也容易显得机械；把长句整理成自然短句，通常会更接近日常表达。"

        let verbatim = try generate(
            mode: .verbatim,
            sourceText: sourceText,
            voice: voice,
            root: root.appendingPathComponent("verbatim", isDirectory: true),
            destination: outputDirectory.appendingPathComponent("A-逐字朗读.wav")
        )
        let spoken = try generate(
            mode: .spoken,
            sourceText: sourceText,
            voice: voice,
            root: root.appendingPathComponent("spoken", isDirectory: true),
            destination: outputDirectory.appendingPathComponent("B-自然讲解.wav")
        )

        print("verbatim=\(verbatim.path)")
        print("spoken=\(spoken.path)")
        print("SpokenNarrationIntegration: PASS")
    }

    private static func generate(
        mode: NarrationScriptMode,
        sourceText: String,
        voice: VoiceProfile,
        root: URL,
        destination: URL
    ) throws -> URL {
        let store = ProjectStore(rootDirectory: root.appendingPathComponent("Projects"))
        let script = try RuleSpokenScriptDirector().prepare(sourceText: sourceText, mode: mode)
        var project = NarrationProject(
            name: mode.label,
            sourceText: sourceText,
            voiceID: voice.id,
            scriptMode: mode,
            scriptVersion: script.version,
            outline: script.outline,
            scriptState: script.usedFallback ? .fallback : .completed,
            scriptErrorSummary: script.warning
        )
        project.segments = NarrationDirector().analyze(script: script, voiceID: voice.id)
        try store.save(project)

        let summary = try GenerationQueue(store: store, engine: QwenSpeechEngine()).run(
            projectID: project.id,
            voice: voice
        ) { progress in
            print("\(mode.rawValue):\(progress.completed)/\(progress.total):\(progress.status)")
        }
        guard summary.failed == 0, !summary.cancelled else {
            throw SpokenNarrationIntegrationError.incompleteGeneration
        }
        project = try store.loadProject(id: project.id)
        guard project.segments.allSatisfy({ $0.generationState == .completed }) else {
            throw SpokenNarrationIntegrationError.incompleteGeneration
        }
        try? FileManager.default.removeItem(at: destination)
        _ = try AudioAssembler(store: store).assemble(project: project, destination: destination)
        return destination
    }
}
