import Foundation

enum ContentImportRequest: Equatable, Sendable {
    case plainText(text: String, title: String?)
    case pdf(URL)
}

struct ImportedContent: Equatable, Sendable {
    var source: NarrationSource
    var text: String
}

protocol ContentImporting: Sendable {
    func importContent(from request: ContentImportRequest) async throws -> ImportedContent
}

enum ContentImportError: LocalizedError, Equatable {
    case unsupportedRequest
    case emptyContent
    case contentTooLong(maximum: Int)
    case fileUnavailable
    case unreadablePDF
    case passwordProtectedPDF
    case noExtractableText

    var errorDescription: String? {
        switch self {
        case .unsupportedRequest:
            return "当前导入方式不支持这个内容"
        case .emptyContent:
            return "没有找到可以朗读的文字"
        case .contentTooLong(let maximum):
            return "当前版本每份内容最多支持 \(maximum) 个字，请拆成几份后再导入"
        case .fileUnavailable:
            return "无法读取这个文件，请确认文件仍在原位置且有访问权限"
        case .unreadablePDF:
            return "这个 PDF 已损坏或不是有效的 PDF 文件"
        case .passwordProtectedPDF:
            return "这个 PDF 受到密码保护，当前版本暂时无法导入"
        case .noExtractableText:
            return "这个 PDF 没有可选择的文字，扫描版 PDF 将在后续版本支持"
        }
    }
}

enum ImportedTextValidator {
    static func validate(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContentImportError.emptyContent
        }
        guard text.count <= NarrationProject.maximumCharacterCount else {
            throw ContentImportError.contentTooLong(
                maximum: NarrationProject.maximumCharacterCount
            )
        }
    }

    static func inferredTitle(from text: String, fallback: String = "未命名听读") -> String {
        let firstLine = text
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let firstLine else { return fallback }
        return String(firstLine.prefix(40))
    }
}
