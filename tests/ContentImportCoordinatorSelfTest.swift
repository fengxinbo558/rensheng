import Foundation

private enum ImportCoordinatorTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func coordinatorExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw ImportCoordinatorTestFailure.assertion(message) }
}

private struct StubPDFImporter: ContentImporting {
    let result: Result<ImportedContent, Error>

    func importContent(from request: ContentImportRequest) async throws -> ImportedContent {
        guard case .pdf = request else { throw ContentImportError.unsupportedRequest }
        return try result.get()
    }
}

@main
struct ContentImportCoordinatorSelfTest {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw ImportCoordinatorTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        let store = ProjectStore(rootDirectory: root)
        let coordinator = ContentImportCoordinator(store: store)

        let textProject = try await coordinator.importContent(
            from: .plainText(text: "导入后可以直接生成的正文。", title: "收件箱文章"),
            defaultVoiceID: "voice-a"
        )
        try coordinatorExpect(textProject.importState == .ready, "文字导入后没有进入可生成状态")
        try coordinatorExpect(textProject.name == "收件箱文章", "文字导入标题没有保存")
        try coordinatorExpect(textProject.source.kind == .text, "文字来源类型不正确")
        let reloadedText = try store.loadProject(id: textProject.id)
        try coordinatorExpect(reloadedText.sourceText == textProject.sourceText, "文字导入结果无法重载")

        let originalPDF = root.deletingLastPathComponent().appendingPathComponent("来源.pdf")
        try Data("fixture-pdf".utf8).write(to: originalPDF, options: .atomic)
        let pdfResult = ImportedContent(
            source: NarrationSource(kind: .pdf, title: "本地 PDF"),
            text: "PDF 中提取的正文。"
        )
        let pdfCoordinator = ContentImportCoordinator(
            store: store,
            pdfImporter: StubPDFImporter(result: .success(pdfResult))
        )
        let pdfProject = try await pdfCoordinator.importContent(
            from: .pdf(originalPDF),
            defaultVoiceID: "voice-b"
        )
        try coordinatorExpect(pdfProject.source.managedFileRelativePath == "source/original.pdf", "PDF 没有记录受管副本")
        let managedPDF = try store.resolveProjectFileURL(
            projectID: pdfProject.id,
            relativePath: "source/original.pdf"
        )
        try coordinatorExpect(FileManager.default.fileExists(atPath: managedPDF.path), "PDF 受管副本不存在")
        let managedData = try Data(contentsOf: managedPDF)
        try coordinatorExpect(
            managedData == Data("fixture-pdf".utf8),
            "PDF 受管副本内容不正确"
        )
        try coordinatorExpect(FileManager.default.fileExists(atPath: originalPDF.path), "导入不应删除原 PDF")

        let failingCoordinator = ContentImportCoordinator(
            store: store,
            pdfImporter: StubPDFImporter(result: .failure(ContentImportError.noExtractableText))
        )
        do {
            _ = try await failingCoordinator.importContent(
                from: .pdf(originalPDF),
                defaultVoiceID: "voice-c"
            )
            throw ImportCoordinatorTestFailure.assertion("失败的导入不应返回成功项目")
        } catch ContentImportError.noExtractableText {
            // 预期结果。
        }
        let projects = try store.loadAllProjects()
        guard let failed = projects.first(where: { $0.voiceID == "voice-c" }) else {
            throw ImportCoordinatorTestFailure.assertion("失败项目没有保留")
        }
        try coordinatorExpect(failed.importState == .needsAttention, "失败项目状态不正确")
        try coordinatorExpect(
            failed.importErrorSummary == ContentImportError.noExtractableText.localizedDescription,
            "失败项目没有保存可理解的错误"
        )

        print("ContentImportCoordinatorSelfTest: PASS")
    }
}
