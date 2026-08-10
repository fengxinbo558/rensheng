import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

private func createFile(_ url: URL, executable: Bool = false) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("test".utf8).write(to: url, options: .atomic)
    if executable {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

@main
struct SpeechEngineConfigurationSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw TestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)

        let overridePython = root.appendingPathComponent("override/python")
        let overrideRunner = root.appendingPathComponent("override/qwen_runner.py")
        let overrideModel = root.appendingPathComponent("override/qwen-model", isDirectory: true)
        let overrideDeepFilter = root.appendingPathComponent("override/deepfilter", isDirectory: true)
        try createFile(overridePython, executable: true)
        try createFile(overrideRunner)
        try createFile(overrideModel.appendingPathComponent("config.json"))
        try createFile(overrideDeepFilter.appendingPathComponent("model.safetensors"))

        let overrides = [
            "LOCAL_AUDIO_QWEN_PYTHON": overridePython.path,
            "LOCAL_AUDIO_QWEN_RUNNER": overrideRunner.path,
            "LOCAL_AUDIO_QWEN_MODEL": overrideModel.path,
            "LOCAL_AUDIO_DEEPFILTER_MODEL": overrideDeepFilter.path,
        ]
        let overridden = RuntimeLocator.locateQwenResources(
            environment: overrides,
            resourceURL: nil,
            sourceDirectory: root
        )
        try expect(overridden.isAvailable, "环境变量指定的自然人声资源应当可用")
        try expect(overridden.python.standardizedFileURL == overridePython.standardizedFileURL, "未优先使用指定运行程序")
        try expect(overridden.runner.standardizedFileURL == overrideRunner.standardizedFileURL, "未优先使用指定生成助手")
        try expect(overridden.model.standardizedFileURL == overrideModel.standardizedFileURL, "未优先使用指定自然人声模型")
        try expect(overridden.deepFilterModel.standardizedFileURL == overrideDeepFilter.standardizedFileURL, "未优先使用指定人声整理模型")

        var missingRunner = overrides
        missingRunner["LOCAL_AUDIO_QWEN_RUNNER"] = root.appendingPathComponent("missing-runner.py").path
        let unavailable = RuntimeLocator.locateQwenResources(
            environment: missingRunner,
            resourceURL: nil,
            sourceDirectory: root
        )
        try expect(!unavailable.isAvailable, "缺少生成助手时不应标记为可用")
        try expect(unavailable.missingComponents.contains("自然人声生成助手"), "缺失信息应能让用户理解")

        let portableResources = root.appendingPathComponent("PortableResources", isDirectory: true)
        let bundledPython = portableResources.appendingPathComponent("QwenRuntime/python/bin/python3.12")
        let bundledRunner = portableResources.appendingPathComponent("QwenRuntime/qwen_runner.py")
        let bundledModel = portableResources.appendingPathComponent("Models/Qwen3TTS", isDirectory: true)
        let bundledDeepFilter = portableResources.appendingPathComponent("Models/DeepFilterNet/v3", isDirectory: true)
        try createFile(bundledPython, executable: true)
        try createFile(bundledRunner)
        try createFile(bundledModel.appendingPathComponent("config.json"))
        try createFile(bundledDeepFilter.appendingPathComponent("model.safetensors"))

        let portable = RuntimeLocator.locateQwenResources(
            environment: overrides,
            resourceURL: portableResources,
            sourceDirectory: root,
            portableMode: true
        )
        try expect(portable.isAvailable, "便携包内资源应当可用")
        try expect(portable.python.standardizedFileURL == bundledPython.standardizedFileURL, "便携版不得使用包外运行程序")
        try expect(portable.runner.standardizedFileURL == bundledRunner.standardizedFileURL, "便携版不得使用包外生成助手")
        try expect(portable.model.standardizedFileURL == bundledModel.standardizedFileURL, "便携版不得使用包外自然人声模型")
        try expect(portable.deepFilterModel.standardizedFileURL == bundledDeepFilter.standardizedFileURL, "便携版不得使用包外人声整理模型")

        let expressiveExecutable = root.appendingPathComponent("override/emotion-cosy-probe")
        let expressiveMetallib = root.appendingPathComponent("override/mlx.metallib")
        let expressiveModel = root.appendingPathComponent("override/cosy-model", isDirectory: true)
        let expressiveSpeaker = root.appendingPathComponent("override/campp", isDirectory: true)
        try createFile(expressiveExecutable, executable: true)
        try createFile(expressiveMetallib)
        for file in [
            "config.json", "llm.safetensors", "flow.safetensors",
            "hifigan.safetensors", "speech_tokenizer.safetensors",
        ] {
            try createFile(expressiveModel.appendingPathComponent(file))
        }
        try createFile(
            expressiveSpeaker
                .appendingPathComponent("CamPlusPlus.mlmodelc")
                .appendingPathComponent("model.mil")
        )
        let expressiveOverrides = [
            "LOCAL_AUDIO_EXPRESSIVE_EXECUTABLE": expressiveExecutable.path,
            "LOCAL_AUDIO_EXPRESSIVE_METALLIB": expressiveMetallib.path,
            "LOCAL_AUDIO_EXPRESSIVE_MODEL": expressiveModel.path,
            "LOCAL_AUDIO_EXPRESSIVE_SPEAKER_MODEL": expressiveSpeaker.path,
        ]
        let expressive = RuntimeLocator.locateExpressiveResources(
            environment: expressiveOverrides,
            resourceURL: nil,
            sourceDirectory: root
        )
        try expect(expressive.isAvailable, "环境变量指定的情绪人声资源应当可用")

        let bundledExpressiveExecutable = portableResources
            .appendingPathComponent("EmotionRuntime/bin/emotion-cosy-probe")
        let bundledExpressiveMetallib = portableResources
            .appendingPathComponent("EmotionRuntime/bin/mlx.metallib")
        let bundledExpressiveModel = portableResources
            .appendingPathComponent("Models/CosyVoice3", isDirectory: true)
        let bundledExpressiveSpeaker = portableResources
            .appendingPathComponent("Models/CamPlusPlus", isDirectory: true)
        try createFile(bundledExpressiveExecutable, executable: true)
        try createFile(bundledExpressiveMetallib)
        for file in [
            "config.json", "llm.safetensors", "flow.safetensors",
            "hifigan.safetensors", "speech_tokenizer.safetensors",
        ] {
            try createFile(bundledExpressiveModel.appendingPathComponent(file))
        }
        try createFile(
            bundledExpressiveSpeaker
                .appendingPathComponent("CamPlusPlus.mlmodelc")
                .appendingPathComponent("model.mil")
        )
        let portableExpressive = RuntimeLocator.locateExpressiveResources(
            environment: expressiveOverrides,
            resourceURL: portableResources,
            sourceDirectory: root,
            portableMode: true
        )
        try expect(portableExpressive.isAvailable, "便携包内情绪资源应当可用")
        try expect(
            portableExpressive.executable.standardizedFileURL
                == bundledExpressiveExecutable.standardizedFileURL,
            "便携版不得使用包外情绪运行程序"
        )

        try expect(
            SpeechEngineProgress.generating(completedChunks: 3).statusLabel.contains("3 个片段"),
            "生成进度应显示已完成的片段数"
        )

        print("SpeechEngineConfigurationSelfTest: PASS")
    }
}
