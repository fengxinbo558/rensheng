import Foundation

final class ProjectStore: @unchecked Sendable {
    typealias AtomicWriter = @Sendable (Data, URL) throws -> Void

    let rootDirectory: URL
    private let atomicWriter: AtomicWriter
    private let fileManager: FileManager

    init(
        rootDirectory: URL = ProbeConfiguration.projectsDirectory,
        fileManager: FileManager = .default,
        atomicWriter: AtomicWriter? = nil
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter ?? { data, destination in
            try data.write(to: destination, options: .atomic)
        }
    }

    func createProject(name: String, sourceText: String, voiceID: String) throws -> NarrationProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = NarrationProject(
            name: cleanName.isEmpty ? "未命名朗读" : cleanName,
            sourceText: sourceText,
            voiceID: voiceID
        )
        try save(project)
        return project
    }

    func createCapturedProject(
        name: String,
        voiceID: String,
        source: NarrationSource
    ) throws -> NarrationProject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = NarrationProject(
            name: cleanName.isEmpty ? "等待导入的内容" : cleanName,
            sourceText: "",
            source: source,
            importState: .captured,
            voiceID: voiceID
        )
        try save(project)
        return project
    }

    func save(_ project: NarrationProject) throws {
        try validate(project: project)
        let directory = try projectDirectory(for: project.id)
        try createProjectDirectories(at: directory)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try atomicWriter(data, directory.appendingPathComponent("project.json"))
    }

    func loadProject(id: String) throws -> NarrationProject {
        let projectFile = try projectDirectory(for: id)
            .appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: projectFile.path) else {
            throw ProjectStoreError.projectNotFound
        }
        let data = try Data(contentsOf: projectFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NarrationProject.self, from: data)
        return decoded.migratedToCurrentVersion()
    }

    func loadAllProjects() throws -> [NarrationProject] {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let contents = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { directory in
            guard UUID(uuidString: directory.lastPathComponent) != nil else { return nil }
            return try? loadProject(id: directory.lastPathComponent)
        }.sorted {
            ($0.lastPlayedAt ?? $0.updatedAt) > ($1.lastPlayedAt ?? $1.updatedAt)
        }
    }

    func deleteProject(id: String) throws {
        let directory = try projectDirectory(for: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw ProjectStoreError.projectNotFound
        }
        try fileManager.trashItem(at: directory, resultingItemURL: nil)
    }

    func projectDirectory(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else {
            throw ProjectStoreError.invalidProjectID
        }
        let candidate = rootDirectory.appendingPathComponent(id, isDirectory: true)
            .standardizedFileURL
        let safePrefix = rootDirectory.path.hasSuffix("/")
            ? rootDirectory.path
            : rootDirectory.path + "/"
        guard candidate.path.hasPrefix(safePrefix) else {
            throw ProjectStoreError.invalidProjectID
        }
        return candidate
    }

    func resolveProjectFileURL(projectID: String, relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              (relativePath as NSString).pathComponents.allSatisfy({ $0 != ".." })
        else {
            throw ProjectStoreError.invalidRelativePath
        }
        let directory = try projectDirectory(for: projectID)
        let candidate = directory.appendingPathComponent(relativePath).standardizedFileURL
        let safePrefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard candidate.path.hasPrefix(safePrefix) else {
            throw ProjectStoreError.invalidRelativePath
        }
        return candidate
    }

    private func createProjectDirectories(at directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for child in ["source", "segments", "previews", "final"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func validate(project: NarrationProject) throws {
        let sourceText = project.sourceText
        if project.importState == .ready,
           sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProjectStoreError.emptyText
        }
        guard sourceText.count <= NarrationProject.maximumCharacterCount else {
            throw ProjectStoreError.textTooLong
        }
    }
}

enum ProjectStoreError: LocalizedError {
    case emptyText
    case textTooLong
    case invalidProjectID
    case invalidRelativePath
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "请输入要朗读的文字"
        case .textTooLong:
            return "当前版本每个项目最多支持 \(NarrationProject.maximumCharacterCount) 个字"
        case .invalidProjectID:
            return "项目标识无效"
        case .invalidRelativePath:
            return "项目文件路径无效"
        case .projectNotFound:
            return "没有找到这个声音作品"
        }
    }
}
