import Foundation

struct QwenRuntimeResources: Equatable {
    let python: URL
    let runner: URL
    let model: URL
    let deepFilterModel: URL

    var missingComponents: [String] {
        var missing: [String] = []
        if !FileManager.default.isExecutableFile(atPath: python.path) {
            missing.append("本地自然人声运行程序")
        }
        if !FileManager.default.isReadableFile(atPath: runner.path) {
            missing.append("自然人声生成助手")
        }
        if !FileManager.default.fileExists(atPath: model.appendingPathComponent("config.json").path) {
            missing.append("自然人声模型")
        }
        if !FileManager.default.fileExists(
            atPath: deepFilterModel.appendingPathComponent("model.safetensors").path
        ) {
            missing.append("人声整理模型")
        }
        return missing
    }

    var isAvailable: Bool {
        missingComponents.isEmpty
    }
}

struct ExpressiveRuntimeResources: Equatable {
    let executable: URL
    let metallib: URL
    let model: URL
    let speakerModel: URL

    var missingComponents: [String] {
        var missing: [String] = []
        if !FileManager.default.isExecutableFile(atPath: executable.path) {
            missing.append("本地情绪人声运行程序")
        }
        if !FileManager.default.isReadableFile(atPath: metallib.path) {
            missing.append("本地情绪人声计算资源")
        }
        for file in [
            "config.json", "llm.safetensors", "flow.safetensors",
            "hifigan.safetensors", "speech_tokenizer.safetensors",
        ] where !FileManager.default.isReadableFile(
            atPath: model.appendingPathComponent(file).path
        ) {
            missing.append("本地情绪人声模型")
            break
        }
        if !FileManager.default.isReadableFile(
            atPath: speakerModel
                .appendingPathComponent("CamPlusPlus.mlmodelc")
                .appendingPathComponent("model.mil").path
        ) {
            missing.append("个人音色识别模型")
        }
        return missing
    }

    var isAvailable: Bool { missingComponents.isEmpty }
}

enum RuntimeLocator {
#if PORTABLE_RUNTIME
    private static let compiledSourceDirectory = URL(fileURLWithPath: "/", isDirectory: true)
#else
    private static let compiledSourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
#endif

    static var qwen: QwenRuntimeResources {
        locateQwenResources()
    }

    static var expressive: ExpressiveRuntimeResources {
        locateExpressiveResources()
    }

    static func locateExpressiveResources(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resourceURL: URL? = Bundle.main.resourceURL,
        sourceDirectory: URL = compiledSourceDirectory,
        portableMode: Bool = Bundle.main.object(forInfoDictionaryKey: "LocalAudioPortableRuntime") as? Bool
            ?? false
    ) -> ExpressiveRuntimeResources {
        let bundledBin = resourceURL?.appendingPathComponent("EmotionRuntime/bin")
        let bundledModel = resourceURL?.appendingPathComponent("Models/CosyVoice3")
        let bundledSpeaker = resourceURL?.appendingPathComponent("Models/CamPlusPlus")
        let developerRuntime = sourceDirectory.appendingPathComponent(
            ".emotion-runtime/swift-probe-build/release"
        )
        let developerModels = sourceDirectory.appendingPathComponent(".emotion-models")

        let executable = locate(
            environmentKey: "LOCAL_AUDIO_EXPRESSIVE_EXECUTABLE",
            environment: environment,
            bundled: bundledBin?.appendingPathComponent("emotion-cosy-probe"),
            developer: developerRuntime.appendingPathComponent("emotion-cosy-probe"),
            portableMode: portableMode
        )
        return ExpressiveRuntimeResources(
            executable: executable,
            metallib: locate(
                environmentKey: "LOCAL_AUDIO_EXPRESSIVE_METALLIB",
                environment: environment,
                bundled: bundledBin?.appendingPathComponent("mlx.metallib"),
                developer: developerRuntime.appendingPathComponent("mlx.metallib"),
                portableMode: portableMode
            ),
            model: locate(
                environmentKey: "LOCAL_AUDIO_EXPRESSIVE_MODEL",
                environment: environment,
                bundled: bundledModel,
                developer: developerModels.appendingPathComponent(
                    "CosyVoice3-0.5B-MLX-8bit-full"
                ),
                portableMode: portableMode
            ),
            speakerModel: locate(
                environmentKey: "LOCAL_AUDIO_EXPRESSIVE_SPEAKER_MODEL",
                environment: environment,
                bundled: bundledSpeaker,
                developer: developerModels.appendingPathComponent(
                    "CamPlusPlus-Speaker-CoreML"
                ),
                portableMode: portableMode
            )
        )
    }

    static func locateQwenResources(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resourceURL: URL? = Bundle.main.resourceURL,
        sourceDirectory: URL = compiledSourceDirectory,
        portableMode: Bool = Bundle.main.object(forInfoDictionaryKey: "LocalAudioPortableRuntime") as? Bool
            ?? false
    ) -> QwenRuntimeResources {
        let workspaceRoot = sourceDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let bundledPython = resourceURL?.appendingPathComponent(
            "QwenRuntime/python/bin/python3.12"
        )
        let bundledRunner = resourceURL?.appendingPathComponent(
            "QwenRuntime/qwen_runner.py"
        )
        let bundledModel = resourceURL?.appendingPathComponent(
            "Models/Qwen3TTS"
        )
        let bundledDeepFilter = resourceURL?.appendingPathComponent(
            "Models/DeepFilterNet/v3"
        )

        let developerProbe = workspaceRoot.appendingPathComponent(
            "spike/qwen3-mlx-python-probe",
            isDirectory: true
        )
        let developerModels = workspaceRoot.appendingPathComponent(
            "spike/models/experimental",
            isDirectory: true
        )

        return QwenRuntimeResources(
            python: locate(
                environmentKey: "LOCAL_AUDIO_QWEN_PYTHON",
                environment: environment,
                bundled: bundledPython,
                developer: developerProbe.appendingPathComponent(".venv/bin/python"),
                portableMode: portableMode
            ),
            runner: locate(
                environmentKey: "LOCAL_AUDIO_QWEN_RUNNER",
                environment: environment,
                bundled: bundledRunner,
                developer: sourceDirectory.appendingPathComponent("Runtime/qwen_runner.py"),
                portableMode: portableMode
            ),
            model: locate(
                environmentKey: "LOCAL_AUDIO_QWEN_MODEL",
                environment: environment,
                bundled: bundledModel,
                developer: developerModels.appendingPathComponent(
                    "qwen3-tts-0.6b-base-8bit",
                    isDirectory: true
                ),
                portableMode: portableMode
            ),
            deepFilterModel: locate(
                environmentKey: "LOCAL_AUDIO_DEEPFILTER_MODEL",
                environment: environment,
                bundled: bundledDeepFilter,
                developer: developerModels.appendingPathComponent(
                    "deepfilternet-mlx/v3",
                    isDirectory: true
                ),
                portableMode: portableMode
            )
        )
    }

    private static func locate(
        environmentKey: String,
        environment: [String: String],
        bundled: URL?,
        developer: URL,
        portableMode: Bool
    ) -> URL {
        if portableMode, let bundled {
            return bundled
        }
        if let override = environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return developer
    }
}
