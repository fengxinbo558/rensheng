import SwiftUI

struct ProjectListView: View {
    @ObservedObject var model: NarrationWorkspaceModel
    let defaultVoiceID: String
    let onDelete: (NarrationProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(StudioPalette.blue)
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("声音导演")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(StudioPalette.ink)
                    Text("离线声音工作台")
                        .font(.caption2)
                        .foregroundStyle(StudioPalette.muted)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("作品库")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioPalette.ink)
                Text("原稿、声音和成品都在本机")
                    .font(.caption)
                    .foregroundStyle(StudioPalette.muted)
            }

            Button {
                model.startNewProject(defaultVoiceID: defaultVoiceID)
            } label: {
                Label("新建声音作品", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isImportingSource)
            .help(model.isImportingSource ? "当前内容导入完成后即可新建" : "新建一份声音作品")

            if model.projects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.title2)
                        .foregroundStyle(Color(red: 0.18, green: 0.41, blue: 0.78))
                    Text("还没有声音作品")
                        .font(.headline)
                        .foregroundStyle(StudioPalette.ink)
                    Text("从右侧粘贴文字或放入 PDF。")
                        .font(.caption)
                        .foregroundStyle(StudioPalette.muted)
                }
                .padding(.vertical, 12)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(model.projects) { project in
                            projectRow(project)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 232)
        .background(StudioPalette.sidebar)
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
                        .foregroundStyle(StudioPalette.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        SourceBadgeView(kind: project.source.kind)
                        Text(projectStatus(project, completed: completed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(project.importState == .needsAttention ? Color.orange : StudioPalette.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开声音作品：\(project.name)，已完成 \(completed) 段")

            Button(role: .destructive) {
                onDelete(project)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除声音作品：\(project.name)")
        }
        .padding(11)
        .background(
            isSelected ? StudioPalette.selectedBlue : StudioPalette.card.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
        }
    }

    private func projectStatus(_ project: NarrationProject, completed: Int) -> String {
        switch project.importState {
        case .captured, .extracting:
            return "正在导入"
        case .needsAttention:
            return "需要处理"
        case .ready:
            if project.listeningCompleted { return "已听完" }
            if project.playbackPositionSeconds > 0 {
                let seconds = Int(project.playbackPositionSeconds.rounded(.down))
                return String(format: "继续 %d:%02d", seconds / 60, seconds % 60)
            }
            return project.segments.isEmpty
                ? "等待制作"
                : "\(completed) / \(project.segments.count) 段"
        }
    }
}
