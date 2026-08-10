import SwiftUI

struct PublishingProgressView: View {
    let progress: PublishingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("出版进度")
                        .font(.headline)
                    Text("生成进度自动保存，不需要按顺序操作")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("本地项目", systemImage: "internaldrive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.23, green: 0.44, blue: 0.78))
            }

            HStack(spacing: 0) {
                ForEach(Array(progress.milestones.enumerated()), id: \.element.id) { index, item in
                    milestone(item)
                    if index < progress.milestones.count - 1 {
                        Rectangle()
                            .fill(connectorColor(after: item))
                            .frame(height: 2)
                            .frame(maxWidth: 34)
                            .padding(.horizontal, 5)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(17)
        .background(
            Color(red: 0.965, green: 0.976, blue: 0.993),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.23, green: 0.44, blue: 0.78).opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("声音作品出版进度")
    }

    private func milestone(_ item: PublishingMilestone) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(item.state))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(stateColor(item.state))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.09, green: 0.14, blue: 0.23))
                Text(item.detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title)：\(stateLabel(item.state))，\(item.detail)")
    }

    private func connectorColor(after item: PublishingMilestone) -> Color {
        item.state == .completed
            ? Color(red: 0.23, green: 0.44, blue: 0.78).opacity(0.45)
            : Color(red: 0.86, green: 0.89, blue: 0.94)
    }

    private func iconName(_ state: PublishingMilestoneState) -> String {
        switch state {
        case .waiting: return "circle"
        case .active: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .needsAttention: return "exclamationmark.circle.fill"
        }
    }

    private func stateColor(_ state: PublishingMilestoneState) -> Color {
        switch state {
        case .waiting: return .secondary
        case .active: return Color(red: 0.23, green: 0.44, blue: 0.78)
        case .completed: return Color(red: 0.15, green: 0.55, blue: 0.46)
        case .needsAttention: return Color(red: 0.76, green: 0.42, blue: 0.15)
        }
    }

    private func stateLabel(_ state: PublishingMilestoneState) -> String {
        switch state {
        case .waiting: return "等待"
        case .active: return "进行中"
        case .completed: return "已完成"
        case .needsAttention: return "需要处理"
        }
    }
}
