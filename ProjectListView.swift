import SwiftUI

struct ProjectListView: View {
    @ObservedObject var model: NarrationWorkspaceModel
    let defaultVoiceID: String
    let onDelete: (NarrationProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("我的朗读")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("文章与音频都只保存在本机")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.startNewProject(defaultVoiceID: defaultVoiceID)
            } label: {
                Label("新建朗读项目", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if model.projects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.title2)
                        .foregroundStyle(Color(red: 0.18, green: 0.41, blue: 0.78))
                    Text("还没有保存的项目")
                        .font(.headline)
                    Text("从右侧粘贴第一篇文章。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.projects) { project in
                            projectRow(project)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 245)
        .background(Color(red: 0.945, green: 0.962, blue: 0.98))
    }

    private func projectRow(_ project: NarrationProject) -> some View {
        let isSelected = model.selectedProject?.id == project.id
        let completed = project.segments.filter { $0.generationState == .completed }.count
        return HStack(spacing: 8) {
            Button {
                model.selectProject(project)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(project.segments.isEmpty ? "等待分析" : "\(completed) / \(project.segments.count) 段")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开项目：\(project.name)，已完成 \(completed) 段")

            Button(role: .destructive) {
                onDelete(project)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除项目：\(project.name)")
        }
        .padding(11)
        .background(
            isSelected
                ? Color(red: 0.84, green: 0.89, blue: 0.97)
                : Color.white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
        }
    }
}
