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
              "generationState": "generating",
              "unknownSegmentField": 42
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
        try migrationExpect(migrated.segments.count == 1, "旧段落没有保留")
        try migrationExpect(migrated.segments[0].expression == .natural, "旧段落应补默认表达方式")
        try migrationExpect(migrated.segments[0].speed == .normal, "旧段落应补默认速度")
        try migrationExpect(migrated.segments[0].pause == .normal, "旧段落应补默认停顿")
        try migrationExpect(migrated.segments[0].generationState == .pending, "遗留生成状态应恢复为等待")
        try migrationExpect(!migrated.segments[0].inputFingerprint.isEmpty, "迁移后应补输入指纹")

        try store.save(migrated)
        let reloaded = try store.loadProject(id: projectID)
        try migrationExpect(reloaded.formatVersion == NarrationProject.currentFormatVersion, "迁移结果无法重新保存")
        try migrationExpect(reloaded.name == "旧项目", "迁移不应改动项目内容")

        print("ProjectMigrationSelfTest: PASS")
    }
}
