import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SourceImportView: View {
    let isBusy: Bool
    let onImportText: (String) -> Void
    let onImportPDF: (URL) -> Void
    let onImportWebPage: (URL) -> Void

    @State private var showingPDFPicker = false
    @State private var localMessage: String?
    @State private var isDropTargeted = false
    @State private var webAddress = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(StudioPalette.blue)
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("放进一份要制作的内容")
                        .font(.headline)
                    Text("粘贴文字，或拖入一份有可选择文字的 PDF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在导入内容")
                }
            }

            HStack(spacing: 10) {
                Button {
                    importClipboardText()
                } label: {
                    Label("粘贴文字", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
                .help("读取剪贴板里的文字并保存为声音作品")

                Button {
                    showingPDFPicker = true
                } label: {
                    Label("选择 PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Text("也可以直接在下面输入或编辑")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                TextField("粘贴网页链接", text: $webAddress)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("网页链接")
                    .accessibilityHint("网页获取需要联网，导入后的生成和保存仍在本机完成")
                    .onSubmit { importWebPage() }
                Button("导入网页") { importWebPage() }
                    .disabled(isBusy || webAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("网页获取阶段需要联网；正文提取、语音生成和项目保存仍在本机完成。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let localMessage {
                Label(localMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("导入提示：\(localMessage)")
            }
        }
        .padding(15)
        .background(isDropTargeted ? StudioPalette.selectedBlue : StudioPalette.card.opacity(0.90), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isDropTargeted
                        ? StudioPalette.blue
                        : StudioPalette.line.opacity(0.6),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7, 5])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isBusy,
                  let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else {
                localMessage = "当前拖放入口只支持 PDF"
                return false
            }
            localMessage = nil
            onImportPDF(pdf)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .fileImporter(
            isPresented: $showingPDFPicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                localMessage = nil
                onImportPDF(url)
            case .failure(let error):
                localMessage = "没有选择 PDF：\(error.localizedDescription)"
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("内容导入")
        .accessibilityHint("可以粘贴文字、选择 PDF，或把 PDF 拖到这里")
    }

    private func importClipboardText() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localMessage = "剪贴板里没有文字，也可以直接在下面输入"
            return
        }
        localMessage = nil
        onImportText(text)
    }

    private func importWebPage() {
        let clean = webAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let normalized = clean.contains("://") ? clean : "https://\(clean)"
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            localMessage = "请输入正确的网页链接"
            return
        }
        localMessage = nil
        webAddress = ""
        onImportWebPage(url)
    }
}
