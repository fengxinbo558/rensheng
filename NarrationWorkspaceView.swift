import SwiftUI

struct NarrationWorkspaceView: View {
    @ObservedObject var model: NarrationWorkspaceModel
    @ObservedObject var voiceLibrary: VoiceLibrary
    let onManageVoices: () -> Void
    @State private var projectToDelete: NarrationProject?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            ProjectListView(
                model: model,
                defaultVoiceID: voiceLibrary.selectedProfile.id,
                onDelete: { project in
                    projectToDelete = project
                    showingDeleteConfirmation = true
                }
            )
            Divider()
            ProjectEditorView(
                model: model,
                voiceLibrary: voiceLibrary,
                onManageVoices: onManageVoices
            )
        }
        .confirmationDialog(
            "删除朗读项目？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                guard let projectToDelete else { return }
                model.deleteProject(
                    projectToDelete,
                    defaultVoiceID: voiceLibrary.selectedProfile.id
                )
                self.projectToDelete = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("“\(projectToDelete?.name ?? "这个项目")”的文字和本地音频会移到废纸篓。")
        }
    }
}
