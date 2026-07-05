import SwiftUI

/// 主布局视图
struct ContentView: View {
    @Environment(NotesViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView()
        } detail: {
            if viewModel.selectedNote != nil {
                EditorView()
            } else {
                emptyStateView
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { viewModel.triggerSync() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .rotationEffect(.degrees(viewModel.syncEngine.status == .syncing ? 360 : 0))
                        .animation(
                            viewModel.syncEngine.status == .syncing ?
                            Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default,
                            value: viewModel.syncEngine.status == .syncing
                        )
                }
                .help("同步到 WebDAV")
                .disabled(viewModel.syncEngine.status == .syncing)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.createNewNote() }) {
                    Label("新建笔记", systemImage: "square.and.pencil")
                }
                .help("新建笔记 (⌘N)")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { viewModel.triggerSync() }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("选择一个笔记开始编辑")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("或按 ⌘N 新建笔记")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
