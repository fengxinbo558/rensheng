import Foundation
import PDFKit

struct PDFTextImporter: ContentImporting {
    func importContent(from request: ContentImportRequest) async throws -> ImportedContent {
        guard case .pdf(let sourceURL) = request else {
            throw ContentImportError.unsupportedRequest
        }
        let url = sourceURL.standardizedFileURL
        guard url.isFileURL,
              url.pathExtension.lowercased() == "pdf",
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw ContentImportError.fileUnavailable
        }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ContentImportError.unreadablePDF
        }
        guard !document.isLocked else {
            throw ContentImportError.passwordProtectedPDF
        }

        var pages: [String] = []
        pages.reserveCapacity(document.pageCount)
        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex), let pageText = page.string else {
                continue
            }
            let normalized = normalizePageText(pageText)
            if !normalized.isEmpty {
                pages.append(normalized)
            }
        }
        let text = pages.joined(separator: "\n\n")
        guard !text.isEmpty else {
            throw ContentImportError.noExtractableText
        }
        try ImportedTextValidator.validate(text)

        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedContent(
            source: NarrationSource(
                kind: .pdf,
                title: title.isEmpty ? "未命名 PDF" : title
            ),
            text: text
        )
    }

    private func normalizePageText(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedNewlines.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        var result: [String] = []
        var previousWasEmpty = false
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !previousWasEmpty, !result.isEmpty {
                    result.append("")
                }
                previousWasEmpty = true
            } else {
                result.append(line)
                previousWasEmpty = false
            }
        }
        while result.last?.isEmpty == true {
            result.removeLast()
        }
        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
