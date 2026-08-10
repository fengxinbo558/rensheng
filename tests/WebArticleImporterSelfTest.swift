import Foundation

private enum WebImporterTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func webExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw WebImporterTestFailure.assertion(message) }
}

private struct FixtureWebPageLoader: WebPageLoading {
    let page: DownloadedWebPage

    func load(url: URL) async throws -> DownloadedWebPage { page }
}

@main
struct WebArticleImporterSelfTest {
    @MainActor
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturesPath = environment["LOCAL_AUDIO_PROBE_TEST_FIXTURES"] else {
            throw WebImporterTestFailure.assertion("缺少测试素材目录")
        }
        let fixtureURL = URL(fileURLWithPath: fixturesPath)
            .appendingPathComponent("article-noise.html")
        let htmlData = try Data(contentsOf: fixtureURL)
        let sourceURL = URL(string: "https://example.com/articles/offline-listening")!
        let loader = FixtureWebPageLoader(
            page: DownloadedWebPage(
                data: htmlData,
                finalURL: sourceURL,
                mimeType: "text/html",
                textEncodingName: "utf-8"
            )
        )
        let importer = WebArticleImporter(loader: loader)
        let imported = try await importer.importContent(from: .webPage(sourceURL))

        try webExpect(imported.source.kind == .webPage, "网页来源类型不正确")
        try webExpect(imported.source.originalURLString == sourceURL.absoluteString, "网页原始链接没有保存")
        try webExpect(imported.source.title == "网页标题", "Readability 没有提取网页标题")
        try webExpect(imported.text.contains("许多人保存了大量文章"), "网页正文没有提取")
        try webExpect(imported.text.contains("真正有用的产品"), "网页后续段落没有保留")
        try webExpect(!imported.text.contains("首页 产品 价格"), "导航被错误放入正文")
        try webExpect(!imported.text.contains("广告："), "广告被错误放入正文")
        try webExpect(!imported.text.contains("评论区："), "评论被错误放入正文")
        try webExpect(!imported.text.contains("页面脚本已经执行"), "导入网页时执行了页面脚本")

        do {
            _ = try await importer.importContent(from: .webPage(URL(string: "file:///tmp/private")!))
            throw WebImporterTestFailure.assertion("本地文件 URL 不应作为网页导入")
        } catch ContentImportError.invalidWebURL {
            // 预期结果。
        }

        print("WebArticleImporterSelfTest: PASS")
    }
}
