import Foundation

final class ContentImportCoordinator: @unchecked Sendable {
    private let store: ProjectStore
    private let plainTextImporter: any ContentImporting
    private let pdfImporter: any ContentImporting
    private let fileManager: FileManager

    init(
        store: ProjectStore,
        plainTextImporter: any ContentImporting = PlainTextImporter(),
        pdfImporter: any ContentImporting = PDFTextImporter(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.plainTextImporter = plainTextImporter
        self.pdfImporter = pdfImporter
        self.fileManager = fileManager
    }

    func importContent(
        from request: ContentImportRequest,
        defaultVoiceID: String
    ) async throws -> NarrationProject {
        var project = try store.createCapturedProject(
            name: preliminaryTitle(for: request),
            voiceID: defaultVoiceID,
            source: preliminarySource(for: request)
        )
        project.importState = .extracting
        project.importErrorSummary = nil
        project.updatedAt = Date()
        try store.save(project)

        do {
            try Task.checkCancellation()
            let preparedRequest = try prepareManagedSource(for: request, project: &project)
            let imported = try await importer(for: preparedRequest).importContent(
                from: preparedRequest
            )
            try Task.checkCancellation()

            var source = imported.source
            source.originalURLString = project.source.originalURLString
            source.managedFileRelativePath = project.source.managedFileRelativePath
            source.importedAt = project.source.importedAt
            project.name = source.title
            project.source = source
            project.sourceText = imported.text
            project.importState = .ready
            project.importErrorSummary = nil
            project.updatedAt = Date()
            try store.save(project)
            return project
        } catch is CancellationError {
            project.importState = .captured
            project.importErrorSummary = nil
            project.updatedAt = Date()
            try? store.save(project)
            throw CancellationError()
        } catch {
            project.importState = .needsAttention
            project.importErrorSummary = error.localizedDescription
            project.updatedAt = Date()
            try? store.save(project)
            throw error
        }
    }

    private func importer(for request: ContentImportRequest) -> any ContentImporting {
        switch request {
        case .plainText:
            return plainTextImporter
        case .pdf:
            return pdfImporter
        }
    }

    private func preliminaryTitle(for request: ContentImportRequest) -> String {
        switch request {
        case .plainText(let text, let title):
            let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cleanTitle, !cleanTitle.isEmpty { return cleanTitle }
            return ImportedTextValidator.inferredTitle(from: text)
        case .pdf(let url):
            let title = url.deletingPathExtension().lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "等待导入的 PDF" : title
        }
    }

    private func preliminarySource(for request: ContentImportRequest) -> NarrationSource {
        let title = preliminaryTitle(for: request)
        switch request {
        case .plainText:
            return NarrationSource(kind: .text, title: title)
        case .pdf(let url):
            return NarrationSource(
                kind: .pdf,
                title: title,
                originalURLString: url.standardizedFileURL.absoluteString,
                managedFileRelativePath: "source/original.pdf"
            )
        }
    }

    private func prepareManagedSource(
        for request: ContentImportRequest,
        project: inout NarrationProject
    ) throws -> ContentImportRequest {
        guard case .pdf(let sourceURL) = request,
              let relativePath = project.source.managedFileRelativePath else {
            return request
        }
        let destination = try store.resolveProjectFileURL(
            projectID: project.id,
            relativePath: relativePath
        )
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw ContentImportError.fileUnavailable
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return .pdf(destination)
    }
}
