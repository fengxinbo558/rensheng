import Foundation

private enum GenerationQueueTestFailure: Error, CustomStringConvertible {
    case assertion(String)
    case plannedFailure

    var description: String {
        switch self {
        case .assertion(let message): return message
        case .plannedFailure: return "计划内失败"
        }
    }
}

private func queueExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw GenerationQueueTestFailure.assertion(message) }
}

private final class FakeSpeechEngine: SpeechEngine, @unchecked Sendable {
    let displayName = "测试引擎"
    let isAvailable = true
    let unavailableReason: String? = nil
    var calls: [String] = []
    var seeds: [Int] = []
    var expressions: [NarrationExpression] = []
    var intensities: [ExpressionIntensity] = []
    var failuresRemaining: [String: Int] = [:]
    var onSynthesize: (() -> Void)?
    private(set) var wasCancelled = false

    func synthesize(
        request: SpeechSynthesisRequest,
        progress: @escaping (SpeechEngineProgress) -> Void
    ) throws -> SpeechSynthesisResult {
        calls.append(request.text)
        seeds.append(request.seed)
        expressions.append(request.expression)
        intensities.append(request.expressionIntensity)
        onSynthesize?()
        if wasCancelled { throw SpeechEngineError.cancelled }
        if let remaining = failuresRemaining[request.text], remaining > 0 {
            failuresRemaining[request.text] = remaining - 1
            throw GenerationQueueTestFailure.plannedFailure
        }
        try FileManager.default.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: 128).write(to: request.outputURL, options: .atomic)
        return SpeechSynthesisResult(outputURL: request.outputURL, warning: nil)
    }

    func cancel() {
        wasCancelled = true
    }
}

@main
struct GenerationQueueSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw GenerationQueueTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("QueueProjects", isDirectory: true)
        let store = ProjectStore(rootDirectory: root)
        let voice = VoiceProfile(
            id: "queue-voice",
            name: "队列测试音色",
            referenceAudioPath: root.appendingPathComponent("reference.wav").path,
            originalAudioPath: nil,
            processedAudioPath: nil,
            qualitySummary: nil,
            referenceText: "参考原文",
            createdAt: Date(),
            authorizationConfirmedAt: Date(),
            isBuiltIn: false
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 64).write(to: voice.referenceAudioURL)

        var project = try store.createProject(
            name: "队列恢复",
            sourceText: "第一段。第二段。第三段。",
            voiceID: voice.id
        )
        project.segments = ["第一段。", "第二段。", "第三段。"].enumerated().map {
            NarrationSegment(
                order: $0.offset,
                text: $0.element,
                kind: .explanation,
                voiceID: voice.id
            )
        }
        try store.save(project)

        let engine = FakeSpeechEngine()
        engine.failuresRemaining["第二段。"] = 1
        let queue = GenerationQueue(
            store: store,
            engine: engine,
            outputValidator: { url in
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw SpeechEngineError.missingOutput
                }
                return 1.0
            }
        )
        let firstRun = try queue.run(projectID: project.id, voice: voice)
        try queueExpect(firstRun.completed == 3, "一次临时失败应自动重试并完成")
        try queueExpect(engine.calls == ["第一段。", "第二段。", "第二段。", "第三段。"], "队列顺序或重试次数不正确")
        try queueExpect(engine.seeds == [42, 42, 43, 42], "自动重试应更换生成变化")

        let callsBeforeCache = engine.calls.count
        let cachedRun = try queue.run(projectID: project.id, voice: voice)
        try queueExpect(cachedRun.skipped == 3, "相同输入应复用已完成音频")
        try queueExpect(engine.calls.count == callsBeforeCache, "缓存命中不应再次生成")

        var oneChanged = try store.loadProject(id: project.id)
        oneChanged.segments[1].expression = .happy
        oneChanged.refreshSegmentFingerprints(invalidateChanged: true)
        try store.save(oneChanged)
        _ = try queue.run(projectID: project.id, voice: voice)
        try queueExpect(engine.calls.last == "第二段。", "只应重新生成修改过的段落")
        try queueExpect(engine.calls.count == callsBeforeCache + 1, "未修改段落不应重做")
        try queueExpect(engine.expressions.last == .happy, "表达设置没有传给语音引擎")
        try queueExpect(engine.intensities.last == .subtle, "默认情绪强度应为轻微")

        var targetedProject = try store.loadProject(id: project.id)
        let targetedID = targetedProject.segments[0].id
        let oldCandidateCount = targetedProject.segments[0].candidates.count
        let untouchedCandidateIDs = targetedProject.segments[1].candidates.map(\.id)
        targetedProject.segments[0].generationState = .pending
        targetedProject.segments[0].selectedCandidateID = nil
        try store.save(targetedProject)
        let callsBeforeTargetedRun = engine.calls.count
        let targetedRun = try queue.run(
            projectID: project.id,
            voice: voice,
            onlySegmentID: targetedID
        )
        try queueExpect(targetedRun.completed == 1, "单段重做应完成一个目标段")
        try queueExpect(engine.calls.count == callsBeforeTargetedRun + 1, "单段重做不应生成其他段落")
        let afterTargetedRun = try store.loadProject(id: project.id)
        try queueExpect(
            afterTargetedRun.segments[0].candidates.count == oldCandidateCount + 1,
            "单段重做应保留旧候选并增加新版本"
        )
        try queueExpect(
            afterTargetedRun.segments[1].candidates.map(\.id) == untouchedCandidateIDs,
            "单段重做不应改动其他段落的候选版本"
        )

        do {
            _ = try queue.run(
                projectID: project.id,
                voice: voice,
                onlySegmentID: "missing-segment"
            )
            throw GenerationQueueTestFailure.assertion("不存在的单段标识应返回错误")
        } catch GenerationQueueError.segmentNotFound {
            // 预期结果。
        }

        var recoveryProject = try store.createProject(
            name: "失败恢复",
            sourceText: "甲。乙。丙。",
            voiceID: voice.id
        )
        recoveryProject.segments = ["甲。", "乙。", "丙。"].enumerated().map {
            NarrationSegment(
                order: $0.offset,
                text: $0.element,
                kind: .explanation,
                voiceID: voice.id
            )
        }
        try store.save(recoveryProject)
        let failingEngine = FakeSpeechEngine()
        failingEngine.failuresRemaining["乙。"] = 2
        let failingQueue = GenerationQueue(
            store: store,
            engine: failingEngine,
            outputValidator: { _ in 1.0 }
        )
        let failedRun = try failingQueue.run(projectID: recoveryProject.id, voice: voice)
        try queueExpect(failedRun.completed == 1 && failedRun.failed == 1, "第二次失败后应停在目标段落")
        let afterFailure = try store.loadProject(id: recoveryProject.id)
        try queueExpect(afterFailure.segments[0].generationState == .completed, "失败不应丢失此前成品")
        try queueExpect(afterFailure.segments[1].generationState == .failed, "失败段落应保存状态")
        try queueExpect(afterFailure.segments[2].generationState == .pending, "后续段落应保持等待")

        let recoveryEngine = FakeSpeechEngine()
        let recoveryQueue = GenerationQueue(
            store: store,
            engine: recoveryEngine,
            outputValidator: { _ in 1.0 }
        )
        _ = try recoveryQueue.run(projectID: recoveryProject.id, voice: voice)
        try queueExpect(recoveryEngine.calls == ["乙。", "丙。"], "恢复时应从第一个未完成段落继续")
        try queueExpect(recoveryEngine.seeds == [44, 42], "用户再次继续时不应重复失败种子")

        var cancellationProject = try store.createProject(
            name: "取消恢复",
            sourceText: "一。二。",
            voiceID: voice.id
        )
        cancellationProject.segments = ["一。", "二。"].enumerated().map {
            NarrationSegment(
                order: $0.offset,
                text: $0.element,
                kind: .explanation,
                voiceID: voice.id
            )
        }
        try store.save(cancellationProject)
        let cancellingEngine = FakeSpeechEngine()
        var cancellingQueue: GenerationQueue?
        cancellingQueue = GenerationQueue(
            store: store,
            engine: cancellingEngine,
            outputValidator: { _ in 1.0 }
        )
        cancellingEngine.onSynthesize = { cancellingQueue?.cancel() }
        let cancelledRun = try cancellingQueue!.run(projectID: cancellationProject.id, voice: voice)
        try queueExpect(cancelledRun.cancelled, "取消状态没有返回给调用方")
        try queueExpect(cancellingEngine.calls.count == 1, "取消后不应继续后续段落")
        let afterCancellation = try store.loadProject(id: cancellationProject.id)
        try queueExpect(afterCancellation.segments[0].generationState == .cancelled, "当前段落应保存取消状态")
        try queueExpect(afterCancellation.segments[1].generationState == .pending, "取消不应影响未开始段落")

        print("GenerationQueueSelfTest: PASS")
    }
}
