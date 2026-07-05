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
        }
        .padding(.vertical, 2)
    }
}
