import Foundation

private enum ProjectMigrationTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func migrationExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw ProjectMigrationTestFailure.assertion(message) }
}

@main
struct ProjectMigrationSelfTest {
    static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw ProjectMigrationTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        let projectID = UUID().uuidString
        let projectDirectory = root.appendingPathComponent(projectID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        let completedSegmentID = UUID().uuidString
        let completedCandidateID = UUID().uuidString
        let oldJSON = """
        {
          "formatVersion": 0,
          "id": "\(projectID)",
          "name": "旧项目",
          "sourceText": "旧版本的知识内容。",
          "voiceID": "legacy-voice",
          "createdAt": "2026-08-01T00:00:00Z",
          "futureUnknownField": {"safe": true},
          "segments": [
            {
              "id": "\(UUID().uuidString)",
              "order": 0,
              "text": "旧版本的知识内容。",
              "kind": "explanation",
              "speed": "slower",
              "generationState": "generating",
              "unknownSegmentField": 42
            },
            {
              "id": "\(completedSegmentID)",
              "order": 1,
              "text": "已经生成的旧段落。",
              "kind": "explanation",
              "speed": "faster",
              "inputFingerprint": "legacy-fingerprint",
              "generationState": "completed",
              "selectedCandidateID": "\(completedCandidateID)",
              "candidates": [
                {
                  "id": "\(completedCandidateID)",
                  "relativePath": "segments/legacy.wav",
                  "inputFingerprint": "legacy-fingerprint",
                  "engineName": "旧引擎",
                  "durationSeconds": 2.5,
                  "createdAt": "2026-08-01T00:00:00Z"
                }
              ]
            }
          ]
        }
        """
        try Data(oldJSON.utf8).write(
            to: projectDirectory.appendingPathComponent("project.json"),
            options: .atomic
        )

        let store = ProjectStore(rootDirectory: root)
        let migrated = try store.loadProject(id: projectID)
        try migrationExpect(
            migrated.formatVersion == NarrationProject.currentFormatVersion,
            "旧项目没有迁移到当前版本"
        )
        try migrationExpect(migrated.scriptMode == .verbatim, "旧项目应保持逐字朗读")
        try migrationExpect(migrated.scriptState == .completed, "旧项目口语稿状态应保持可用")
        try migrationExpect(migrated.source.kind == .text, "旧项目应迁移为文字来源")
        try migrationExpect(migrated.source.title == "旧项目", "旧项目来源标题应沿用项目名称")
        try migrationExpect(migrated.importState == .ready, "旧项目应迁移为可生成状态")
        try migrationExpect(migrated.importErrorSummary == nil, "旧项目不应产生导入错误")
        try migrationExpect(migrated.playbackPositionSeconds == 0, "旧项目播放位置应从头开始")
        try migrationExpect(migrated.lastPlayedAt == nil, "旧项目不应虚构播放时间")
        try migrationExpect(!migrated.listeningCompleted, "旧项目不应自动标记听完")
        try migrationExpect(migrated.segments.count == 2, "旧段落没有保留")
        try migrationExpect(
            migrated.segments[0].sourceText == "旧版本的知识内容。",
            "旧段落原文没有保留"
        )
        try migrationExpect(
            migrated.segments[0].spokenText == "旧版本的知识内容。",
            "旧段落朗读稿没有保留"
        )
        try migrationExpect(
            migrated.segments[0].speakerRole == .narrator,
            "旧段落应补默认讲解者角色"
        )
        try migrationExpect(
            !migrated.segments[0].scriptFingerprint.isEmpty,
            "旧段落应补口语稿指纹"
        )
        try migrationExpect(migrated.segments[0].expression == .natural, "旧段落应补默认表达方式")
        try migrationExpect(
            migrated.segments[0].expressionIntensity == .subtle,
            "旧段落应补轻微情绪强度"
        )
        try migrationExpect(migrated.segments[0].speedFactor == 0.9, "旧段落速度应迁移为0.9倍")
        try migrationExpect(migrated.segments[0].pause == .normal, "旧段落应补默认停顿")
        try migrationExpect(migrated.segments[0].generationState == .pending, "遗留生成状态应恢复为等待")
        try migrationExpect(!migrated.segments[0].inputFingerprint.isEmpty, "迁移后应补输入指纹")
        try migrationExpect(migrated.segments[1].speedFactor == 1.1, "旧稍快速度应迁移为1.1倍")
        try migrationExpect(migrated.segments[1].generationState == .completed, "已完成旧段落不应重新生成")
        try migrationExpect(migrated.segments[1].candidates.count == 1, "旧段落母版没有保留")
        try migrationExpect(
            migrated.segments[1].candidates[0].inputFingerprint == migrated.segments[1].inputFingerprint,
            "迁移后母版指纹应同步更新"
        )

        try store.save(migrated)
        let reloaded = try store.loadProject(id: projectID)
        try migrationExpect(reloaded.formatVersion == NarrationProject.currentFormatVersion, "迁移结果无法重新保存")
        try migrationExpect(reloaded.name == "旧项目", "迁移不应改动项目内容")
        try migrationExpect(reloaded.segments[0].speedFactor == 0.9, "精细语速无法重新保存")
        try migrationExpect(reloaded.segments[0].sourceText == reloaded.segments[0].spokenText, "迁移后的双文本无法重存")

        let newProject = NarrationProject(
            name: "新项目",
            sourceText: "适合自然讲解的新内容。",
            voiceID: "voice-new"
        )
        try migrationExpect(newProject.source.kind == .text, "新项目应默认使用文字来源")
        try migrationExpect(newProject.importState == .ready, "带正文的新项目应可直接生成")
        try migrationExpect(newProject.scriptMode == .spoken, "新项目应默认自然讲解")
        try migrationExpect(newProject.scriptState == .pending, "新项目应等待口语整理")
        try migrationExpect(
            !newProject.needsSpokenScriptRefresh(
                currentVersion: RuleSpokenScriptDirector.currentVersion
            ),
            "还没有生成口语稿的新项目不应标记为过期"
        )

        var outdated = newProject
        outdated.scriptState = .completed
        outdated.scriptVersion = "rule-zh-v1"
        try migrationExpect(
            outdated.needsSpokenScriptRefresh(
                currentVersion: RuleSpokenScriptDirector.currentVersion
            ),
            "旧自然讲解项目应在下次生成前更新分段规则"
        )

        outdated.scriptMode = .verbatim
        try migrationExpect(
            !outdated.needsSpokenScriptRefresh(
                currentVersion: RuleSpokenScriptDirector.currentVersion
            ),
            "逐字朗读项目不应被自动改成新口语分段"
        )

        var oldConditioning = NarrationProject(
            name: "旧克隆方式",
            sourceText: "正文第一个字必须保留。",
            voiceID: "voice-old-conditioning"
        )
        oldConditioning.segments = [
            NarrationSegment(
                order: 0,
                text: "正文第一个字必须保留。",
                kind: .explanation,
                voiceID: oldConditioning.voiceID
            )
        ]
        let staleCandidate = NarrationAudioCandidate(
            id: "stale-icl-audio",
            relativePath: "segments/stale.wav",
            inputFingerprint: "legacy-icl-conditioning",
            engineName: "自然人声",
            durationSeconds: 2
        )
        oldConditioning.segments[0].inputFingerprint = "legacy-icl-conditioning"
        oldConditioning.segments[0].generationState = .completed
        oldConditioning.segments[0].candidates = [staleCandidate]
        oldConditioning.segments[0].selectedCandidateID = staleCandidate.id
        try store.save(oldConditioning)

        let refreshedConditioning = try store.loadProject(id: oldConditioning.id)
        try migrationExpect(
            refreshedConditioning.segments[0].generationState == .pending,
            "旧 ICL 音频应在无尾音模式启用后等待重新生成"
        )
        try migrationExpect(
            refreshedConditioning.segments[0].candidates.isEmpty,
            "带参考尾音的旧候选不应继续播放"
        )

        print("ProjectMigrationSelfTest: PASS")
    }
}
