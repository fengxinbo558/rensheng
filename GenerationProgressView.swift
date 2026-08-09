import SwiftUI

struct GenerationProgressView: View {
    let progress: GenerationQueueProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(progress.status, systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(progress.completed) / \(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("暂停", role: .cancel) { onCancel() }
            }
            ProgressView(
                value: Double(progress.completed),
                total: Double(max(progress.total, 1))
            )
            .tint(Color(red: 0.18, green: 0.41, blue: 0.78))
            .accessibilityLabel("全文生成进度")
            .accessibilityValue("已完成 \(progress.completed) 段，共 \(progress.total) 段")
        }
        .padding(14)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
