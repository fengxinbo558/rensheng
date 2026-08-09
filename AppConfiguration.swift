import Foundation

enum ProbeConfiguration {
#if PORTABLE_RUNTIME
    private static let workspaceRoot = URL(fileURLWithPath: "/", isDirectory: true)
#else
    private static let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
    private static let workspaceRoot = sourceDirectory
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
#endif
    private static var isPortable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LocalAudioPortableRuntime") as? Bool ?? false
    }

    static let runtime = bundledResource(
        "Sherpa/bin/sherpa-onnx-offline-tts",
        fallback: workspaceRoot.appendingPathComponent(
            "spike/models/exploratory/sherpa-onnx-v1.13.1-osx-arm64-shared/bin/sherpa-onnx-offline-tts"
        )
    )
    static let denoiserRuntime = bundledResource(
        "Sherpa/bin/sherpa-onnx-offline-denoiser",
        fallback: workspaceRoot.appendingPathComponent(
            "spike/models/exploratory/sherpa-onnx-v1.13.1-osx-arm64-shared/bin/sherpa-onnx-offline-denoiser"
        )
    )
    static let denoiserModel = bundledResource(
        "Models/gtcrn_simple.onnx",
        fallback: workspaceRoot.appendingPathComponent(
            "spike/models/exploratory/sherpa-onnx-speech-enhancement/gtcrn_simple.onnx"
        )
    )
    static let model = bundledResource(
        "Models/ZipVoice",
        fallback: workspaceRoot.appendingPathComponent(
            "spike/models/exploratory/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia",
            isDirectory: true
        )
    )
    static let vocoder = bundledResource(
        "Models/vocos_24khz.onnx",
        fallback: workspaceRoot.appendingPathComponent("spike/models/exploratory/vocos_24khz.onnx")
    )
    static let defaultReferenceAudio = bundledResource(
        "Fixtures/default-reference.wav",
        fallback: workspaceRoot.appendingPathComponent(
            "spike/fixtures/voice-clone-v1/data/system-voice-smoke-reference.wav"
        )
    )
    static let defaultReferenceText = "大家好，欢迎使用本地普通话音频概览。这是一段用于验证离线语音合成功能的参考录音，所有内容都保存在这台电脑上。"

    static var applicationSupportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["LOCAL_AUDIO_PROBE_APP_SUPPORT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalAudioProbe", isDirectory: true)
    }

    static var voicesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Voices", isDirectory: true)
    }

    static var voicesIndexURL: URL {
        applicationSupportDirectory.appendingPathComponent("voices.json")
    }

    static var projectsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Projects", isDirectory: true)
    }

    static var outputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["LOCAL_AUDIO_PROBE_OUTPUT_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let musicDirectory = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
        return musicDirectory.appendingPathComponent("本地音频概览", isDirectory: true)
    }

    static func ensureDataDirectories() throws {
        try FileManager.default.createDirectory(
            at: voicesDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectsDirectory,
            withIntermediateDirectories: true
        )
    }

    private static func bundledResource(_ relativePath: String, fallback: URL) -> URL {
        guard let resources = Bundle.main.resourceURL else { return fallback }
        let candidate = resources.appendingPathComponent(relativePath)
        if isPortable { return candidate }
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : fallback
    }
}
