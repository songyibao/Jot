import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

/// Jot macOS 应用入口
@main
struct JotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = NotesViewModel()

    var body: some Scene {
        WindowGroup {
            if viewModel.isLoggedIn {
                ContentView()
                    .environment(viewModel)
                    .frame(minWidth: 700, minHeight: 500)
            } else {
                LoginView()
                    .environment(viewModel)
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建笔记") {
                    viewModel.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
