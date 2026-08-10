import Foundation
import WebKit

struct ExtractedWebArticle: Equatable, Sendable {
    let title: String
    let text: String
}

protocol WebArticleExtracting: Sendable {
    func extract(html: String, baseURL: URL) async throws -> ExtractedWebArticle
}

struct WKReadabilityExtractor: WebArticleExtracting {
    func extract(html: String, baseURL: URL) async throws -> ExtractedWebArticle {
        let readabilityScript = try ReadabilityScriptLoader.load()
        return try await WebArticleExtractionHost.extract(
            html: html,
            baseURL: baseURL,
            readabilityScript: readabilityScript
        )
    }
}

enum ReadabilityScriptLoader {
    static func load() throws -> String {
        var candidates: [URL] = []
        if let projectPath = ProcessInfo.processInfo.environment["LOCAL_AUDIO_PROBE_PROJECT_DIR"] {
            candidates.append(
                URL(fileURLWithPath: projectPath, isDirectory: true)
                    .appendingPathComponent("ThirdParty/Readability/Readability.js")
            )
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(
                resources.appendingPathComponent("ThirdParty/Readability/Readability.js")
            )
        }
        for url in candidates where FileManager.default.isReadableFile(atPath: url.path) {
            if let script = try? String(contentsOf: url, encoding: .utf8), !script.isEmpty {
                return script
            }
        }
        throw ContentImportError.readabilityUnavailable
    }
}

@MainActor
private final class WebArticleExtractionHost: NSObject, WKNavigationDelegate {
    private let html: String
    private let baseURL: URL
    private let readabilityScript: String
    private let webView: WKWebView
    private var continuation: CheckedContinuation<ExtractedWebArticle, Error>?
    private var timeoutTask: Task<Void, Never>?

    static func extract(
        html: String,
        baseURL: URL,
        readabilityScript: String
    ) async throws -> ExtractedWebArticle {
        let host = WebArticleExtractionHost(
            html: html,
            baseURL: baseURL,
            readabilityScript: readabilityScript
        )
        return try await host.run()
    }

    init(html: String, baseURL: URL, readabilityScript: String) {
        self.html = html
        self.baseURL = baseURL
        self.readabilityScript = readabilityScript
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    private func run() async throws -> ExtractedWebArticle {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(restrictedHTML(html), baseURL: baseURL)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(ContentImportError.articleExtractionFailed))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let extractionScript = """
        \(readabilityScript)
        JSON.stringify((function () {
          var clone = document.cloneNode(true);
          var article = new Readability(clone, {
            charThreshold: 80,
            maxElemsToParse: 50000,
            keepClasses: false
          }).parse();
          if (!article || !article.textContent) return null;
          return { title: article.title || document.title || "", text: article.textContent };
        })());
        """
        webView.evaluateJavaScript(extractionScript) { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error != nil {
                    self.finish(.failure(ContentImportError.articleExtractionFailed))
                    return
                }
                guard let json = value as? String,
                      json != "null",
                      let data = json.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(ExtractionPayload.self, from: data),
                      !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.finish(.failure(ContentImportError.articleExtractionFailed))
                    return
                }
                self.finish(
                    .success(
                        ExtractedWebArticle(
                            title: decoded.title,
                            text: decoded.text
                        )
                    )
                )
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(ContentImportError.articleExtractionFailed))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(ContentImportError.articleExtractionFailed))
    }

    private func finish(_ result: Result<ExtractedWebArticle, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        continuation.resume(with: result)
    }

    private func restrictedHTML(_ source: String) -> String {
        let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\">"
        if let headRange = source.range(of: "<head", options: [.caseInsensitive]),
           let closingBracket = source[headRange.lowerBound...].firstIndex(of: ">") {
            var copy = source
            copy.insert(contentsOf: policy, at: copy.index(after: closingBracket))
            return copy
        }
        return "<!doctype html><html><head>\(policy)</head><body>\(source)</body></html>"
    }

    private struct ExtractionPayload: Decodable {
        let title: String
        let text: String
    }
}
