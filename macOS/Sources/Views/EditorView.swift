import SwiftUI
import AppKit

/// 编辑器视图（纯文本模式）
struct EditorView: View {
    @Environment(NotesViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // 顶部：笔记标题 + 保存状态
            if let note = viewModel.selectedNote {
                HStack {
                    Text(viewModel.notes.first(where: { $0.url == note.url })?.title ?? note.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if viewModel.hasUnsavedChanges {
                        Text("未保存")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
            }

            // 纯文本编辑区
            PlainTextView(text: $vm.currentContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            Button("") {
                viewModel.forceSaveAndSync()
            }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }
}

/// NSTextView 桥接到 SwiftUI（纯文本模式）
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // 纯文本配置：关闭富文本，不需要任何格式渲染
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false

        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // 等宽字体，简洁舒适
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

        // 行间距
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        textView.defaultParagraphStyle = style

        // 内边距
        textView.textContainerInset = NSSize(width: 24, height: 24)

        // 自动换行
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false

        // 系统颜色（自动适配暗色/亮色模式）
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor

        textView.delegate = context.coordinator
        textView.string = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 仅在外部内容变化时更新（避免光标跳动）
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
