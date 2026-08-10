import CoreFoundation
import Foundation

struct DownloadedWebPage: Sendable {
    let data: Data
    let finalURL: URL
    let mimeType: String?
    let textEncodingName: String?
}

protocol WebPageLoading: Sendable {
    func load(url: URL) async throws -> DownloadedWebPage
}

final class URLSessionWebPageLoader: WebPageLoading, @unchecked Sendable {
    static let maximumResponseBytes = 8 * 1_024 * 1_024

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func load(url: URL) async throws -> DownloadedWebPage {
        guard WebArticleImporter.isAllowedWebURL(url) else {
            throw ContentImportError.invalidWebURL
        }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("声音导演/0.4", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let finalURL = http.url,
                  WebArticleImporter.isAllowedWebURL(finalURL) else {
                throw ContentImportError.webRequestFailed
            }
            guard data.count <= Self.maximumResponseBytes else {
                throw ContentImportError.webResponseTooLarge
            }
            let mimeType = http.mimeType?.lowercased()
            guard mimeType == nil
                    || mimeType == "text/html"
                    || mimeType == "application/xhtml+xml" else {
                throw ContentImportError.unsupportedWebContent
            }
            return DownloadedWebPage(
                data: data,
                finalURL: finalURL,
                mimeType: mimeType,
                textEncodingName: http.textEncodingName
            )
        } catch let error as ContentImportError {
            throw error
        } catch {
            throw ContentImportError.webRequestFailed
        }
    }
}

struct WebArticleImporter: ContentImporting {
    private let loader: any WebPageLoading
    private let extractor: any WebArticleExtracting

    init(
        loader: any WebPageLoading = URLSessionWebPageLoader(),
        extractor: any WebArticleExtracting = WKReadabilityExtractor()
    ) {
        self.loader = loader
        self.extractor = extractor
    }

    func importContent(from request: ContentImportRequest) async throws -> ImportedContent {
        guard case .webPage(let requestedURL) = request,
              Self.isAllowedWebURL(requestedURL) else {
            throw ContentImportError.invalidWebURL
        }
        let page = try await loader.load(url: requestedURL)
        try Task.checkCancellation()
        let html = try decode(page: page)
        let extracted = try await extractor.extract(html: html, baseURL: page.finalURL)
        let text = normalize(extracted.text)
        try ImportedTextValidator.validate(text)
        let cleanTitle = normalizeTitle(extracted.title)
        let fallbackTitle = page.finalURL.host ?? "未命名网页"
        return ImportedContent(
            source: NarrationSource(
                kind: .webPage,
                title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
                originalURLString: requestedURL.absoluteString
            ),
            text: text
        )
    }

    static func isAllowedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return false }
        return true
    }

    private func decode(page: DownloadedWebPage) throws -> String {
        if let encodingName = page.textEncodingName,
           let encoding = stringEncoding(named: encodingName),
           let decoded = String(data: page.data, encoding: encoding) {
            return decoded
        }
        if let decoded = String(data: page.data, encoding: .utf8) {
            return decoded
        }
        throw ContentImportError.unreadableWebText
    }

    private func stringEncoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        )
    }

    private func normalize(_ text: String) -> String {
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
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if !previousWasEmpty, !result.isEmpty { result.append("") }
                previousWasEmpty = true
            } else {
                result.append(line)
                previousWasEmpty = false
            }
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
