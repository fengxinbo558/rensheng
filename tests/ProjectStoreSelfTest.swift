import Foundation

private enum ProjectStoreTestFailure: Error, CustomStringConvertible {
    case assertion(String)
    case simulatedWriteFailure

    var description: String {
        switch self {
        case .assertion(let message): return message
        case .simulatedWriteFailure: return "模拟写入失败"
        }
    }
}

private func projectExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw ProjectStoreTestFailure.assertion(message) }
}

@main
struct ProjectStoreSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw ProjectStoreTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        let store = ProjectStore(rootDirectory: root)

        var project = try store.createProject(
            name: "自然朗读测试",
            sourceText: "第一段知识内容。\n\n第二段是一个例子。",
            voiceID: "voice-a"
        )
        project.segments = [
            NarrationSegment(
                order: 0,
                text: "第一段知识内容。",
                kind: .explanation,
                voiceID: project.voiceID
            ),
            NarrationSegment(
                order: 1,
                text: "第二段是一个例子。",
                kind: .example,
                voiceID: project.voiceID
            ),
        ]
        let firstFingerprint = project.segments[0].inputFingerprint
        let secondFingerprint = project.segments[1].inputFingerprint
        let candidate = NarrationAudioCandidate(
            relativePath: "segments/first-a.wav",
            inputFingerprint: firstFingerprint,
            engineName: "自然人声",
            durationSeconds: 3.2
        )
        project.segments[0].candidates = [candidate]
        project.segments[0].selectedCandidateID = candidate.id
        project.segments[0].generationState = .completed
        try store.save(project)

        let loaded = try store.loadProject(id: project.id)
        try projectExpect(loaded.name == project.name, "项目名称没有保存")
        try projectExpect(loaded.sourceText == project.sourceText, "项目原文没有保存")
        try projectExpect(loaded.segments.count == 2, "项目段落没有保存")
        try projectExpect(loaded.segments[0].selectedCandidateID == candidate.id, "已选音频版本没有保存")

        var changed = loaded
        changed.segments[0].expression = .emphasized
        changed.refreshSegmentFingerprints(invalidateChanged: true)
        try projectExpect(changed.segments[0].inputFingerprint != firstFingerprint, "修改朗读设置后指纹应改变")
        try projectExpect(changed.segments[0].candidates.isEmpty, "修改段落后旧音频应失效")
        try projectExpect(changed.segments[0].generationState == .pending, "修改段落后应等待重新生成")
        try projectExpect(changed.segments[1].inputFingerprint == secondFingerprint, "未修改段落不应失效")

        let exactlyLimit = String(repeating: "字", count: NarrationProject.maximumCharacterCount)
        _ = try store.createProject(name: "上限", sourceText: exactlyLimit, voiceID: "voice-a")
        do {
            _ = try store.createProject(
                name: "超限",
                sourceText: exactlyLimit + "字",
                voiceID: "voice-a"
            )
            throw ProjectStoreTestFailure.assertion("超过 3000 字的项目不应创建")
        } catch ProjectStoreError.textTooLong {
            // 预期结果。
        }

        let failingStore = ProjectStore(rootDirectory: root) { _, _ in
            throw ProjectStoreTestFailure.simulatedWriteFailure
        }
        var unsaved = loaded
        unsaved.name = "不应覆盖旧文件"
        do {
            try failingStore.save(unsaved)
            throw ProjectStoreTestFailure.assertion("模拟写入失败应向上报告")
        } catch ProjectStoreTestFailure.simulatedWriteFailure {
            // 预期结果。
        }
        let afterFailure = try store.loadProject(id: project.id)
        try projectExpect(afterFailure.name == project.name, "写入失败不应损坏旧项目")

        do {
            _ = try store.loadProject(id: "../escape")
            throw ProjectStoreTestFailure.assertion("项目路径不得越界")
        } catch ProjectStoreError.invalidProjectID {
            // 预期结果。
        }

        do {
            _ = try store.resolveProjectFileURL(
                projectID: project.id,
                relativePath: "../outside.wav"
            )
            throw ProjectStoreTestFailure.assertion("项目文件路径不得越界")
        } catch ProjectStoreError.invalidRelativePath {
            // 预期结果。
        }

        print("ProjectStoreSelfTest: PASS")
    }
}
