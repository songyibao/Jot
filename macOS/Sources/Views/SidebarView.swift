import SwiftUI

/// 侧边栏：笔记列表
struct SidebarView: View {
    @Environment(NotesViewModel.self) private var viewModel

    var body: some View {
        List(viewModel.notes, selection: Binding(
            get: { viewModel.selectedNote },
            set: { viewModel.selectNote($0) }
        )) { note in
            NoteRow(note: note, viewModel: viewModel)
                .tag(note)
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.deleteNote(note)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
        }
        .listStyle(.sidebar)
        .navigationTitle("Jot")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(viewModel.notes.count) 篇笔记")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// 笔记列表单行
struct NoteRow: View {
    let note: NoteItem
    let viewModel: NotesViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.body)
                    .lineLimit(1)

                Text(note.modifiedDate, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // 同步状态指示灯
            let state = viewModel.syncEngine.fileSyncState(for: note.url, localModifiedDate: note.modifiedDate)
            Circle()
                .fill(stateColor(state))
                .frame(width: 8, height: 8)
                .help(stateHelpText(state))
        }
        .padding(.vertical, 2)
    }

    private func stateColor(_ state: SyncEngine.NoteSyncState) -> Color {
        switch state {
        case .synced:   return .green
        case .pending:  return .yellow
        case .conflict: return .red
        }
    }

    private func stateHelpText(_ state: SyncEngine.NoteSyncState) -> String {
        switch state {
        case .synced:   return "已同步"
        case .pending:  return "待同步（有未上传的修改）"
        case .conflict: return "同步冲突"
        }
    }
}
