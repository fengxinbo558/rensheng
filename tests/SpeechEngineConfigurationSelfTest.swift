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

        try expect(
            SpeechEngineProgress.generating(completedChunks: 3).statusLabel.contains("3 个片段"),
            "生成进度应显示已完成的片段数"
        )

        print("SpeechEngineConfigurationSelfTest: PASS")
    }
}
