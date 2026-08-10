import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SourceImportView: View {
    let isBusy: Bool
    let onImportText: (String) -> Void
    let onImportPDF: (URL) -> Void

    @State private var showingPDFPicker = false
    @State private var localMessage: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.16, green: 0.39, blue: 0.76))
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("放进一个想听的内容")
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
                .help("读取剪贴板里的文字并保存为听读项目")

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

            if let localMessage {
                Label(localMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("导入提示：\(localMessage)")
            }
        }
        .padding(15)
        .background(
            isDropTargeted
                ? Color(red: 0.84, green: 0.91, blue: 0.99)
                : Color.white.opacity(0.76),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isDropTargeted
                        ? Color(red: 0.16, green: 0.39, blue: 0.76)
                        : Color.black.opacity(0.08),
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
}
