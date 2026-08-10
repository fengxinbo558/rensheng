import Foundation

private enum ContentImporterTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func contentExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw ContentImporterTestFailure.assertion(message) }
}

@main
struct ContentImporterSelfTest {
    static func main() async throws {
        let importer = PlainTextImporter()
        let imported = try await importer.importContent(
            from: .plainText(
                text: "第一行是标题\n第二行是正文。",
                title: nil
            )
        )
        try contentExpect(imported.source.kind == .text, "纯文字来源类型不正确")
        try contentExpect(imported.source.title == "第一行是标题", "没有从首行推断标题")
        try contentExpect(
            imported.text == "第一行是标题\n第二行是正文。",
            "纯文字导入不应改写原文"
        )

        let named = try await importer.importContent(
            from: .plainText(text: "正文", title: "  自定义名称  ")
        )
        try contentExpect(named.source.title == "自定义名称", "没有清理自定义标题")

        do {
            _ = try await importer.importContent(from: .plainText(text: "  \n", title: nil))
            throw ContentImporterTestFailure.assertion("空文字不应导入成功")
        } catch ContentImportError.emptyContent {
            // 预期结果。
        }

        let exactlyLimit = String(repeating: "字", count: NarrationProject.maximumCharacterCount)
        _ = try await importer.importContent(from: .plainText(text: exactlyLimit, title: nil))
        do {
            _ = try await importer.importContent(
                from: .plainText(text: exactlyLimit + "字", title: nil)
            )
            throw ContentImporterTestFailure.assertion("超过项目上限的文字不应导入成功")
        } catch ContentImportError.contentTooLong(let maximum) {
            try contentExpect(
                maximum == NarrationProject.maximumCharacterCount,
                "超长错误没有返回正确上限"
            )
        }

        print("ContentImporterSelfTest: PASS")
    }
}
