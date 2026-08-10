import CoreGraphics
import CoreText
import Foundation

private enum PDFImporterTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private func pdfExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw PDFImporterTestFailure.assertion(message) }
}

private func makeSearchablePDF(at url: URL, pages: [String]) throws {
    guard let consumer = CGDataConsumer(url: url as CFURL) else {
        throw PDFImporterTestFailure.assertion("无法创建 PDF consumer")
    }
    var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw PDFImporterTestFailure.assertion("无法创建 PDF context")
    }
    for text in pages {
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 72, y: 760)
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 16, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        context.endPDFPage()
    }
    context.closePDF()
}

@main
struct PDFTextImporterSelfTest {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["LOCAL_AUDIO_PROBE_TEST_ROOT"] else {
            throw PDFImporterTestFailure.assertion("缺少测试目录")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let importer = PDFTextImporter()

        let searchable = root.appendingPathComponent("普通话资料.pdf")
        try makeSearchablePDF(
            at: searchable,
            pages: ["第一页的知识内容。", "第二页继续说明。"]
        )
        let imported = try await importer.importContent(from: .pdf(searchable))
        try pdfExpect(imported.source.kind == .pdf, "PDF 来源类型不正确")
        try pdfExpect(imported.source.title == "普通话资料", "PDF 文件名没有转换为标题")
        let firstRange = imported.text.range(of: "第一页的知识内容。")
        let secondRange = imported.text.range(of: "第二页继续说明。")
        try pdfExpect(firstRange != nil && secondRange != nil, "PDF 页面文字没有完整提取")
        if let firstRange, let secondRange {
            try pdfExpect(firstRange.lowerBound < secondRange.lowerBound, "PDF 页面顺序被打乱")
        }

        let emptyPDF = root.appendingPathComponent("扫描件.pdf")
        try makeSearchablePDF(at: emptyPDF, pages: [""])
        do {
            _ = try await importer.importContent(from: .pdf(emptyPDF))
            throw PDFImporterTestFailure.assertion("没有文字的 PDF 不应导入成功")
        } catch ContentImportError.noExtractableText {
            // 预期结果。
        }

        let damaged = root.appendingPathComponent("损坏.pdf")
        try Data("not a pdf".utf8).write(to: damaged)
        do {
            _ = try await importer.importContent(from: .pdf(damaged))
            throw PDFImporterTestFailure.assertion("损坏 PDF 不应导入成功")
        } catch ContentImportError.unreadablePDF {
            // 预期结果。
        }

        do {
            _ = try await importer.importContent(from: .plainText(text: "错误请求", title: nil))
            throw PDFImporterTestFailure.assertion("PDF importer 不应接受文字请求")
        } catch ContentImportError.unsupportedRequest {
            // 预期结果。
        }

        print("PDFTextImporterSelfTest: PASS")
    }
}
