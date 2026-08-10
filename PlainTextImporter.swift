import Foundation

struct PlainTextImporter: ContentImporting {
    func importContent(from request: ContentImportRequest) async throws -> ImportedContent {
        guard case .plainText(let text, let requestedTitle) = request else {
            throw ContentImportError.unsupportedRequest
        }
        try ImportedTextValidator.validate(text)
        let cleanTitle = requestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let cleanTitle, !cleanTitle.isEmpty {
            title = cleanTitle
        } else {
            title = ImportedTextValidator.inferredTitle(from: text)
        }
        return ImportedContent(
            source: NarrationSource(kind: .text, title: title),
            text: text
        )
    }
}
