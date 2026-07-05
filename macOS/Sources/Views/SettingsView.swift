import SwiftUI

/// 设置视图
struct SettingsView: View {
    @Environment(NotesViewModel.self) private var viewModel

    var body: some View {
        Form {
            Section("WebDAV 同步 (例如坚果云)") {
                TextField("服务器地址 (URL)", text: $webdavURL)
                TextField("账号", text: $webdavUsername)
                SecureField("应用密码", text: $webdavPassword)

                HStack {
                    Button("保存并开启同步") {
                        saveWebDAVSettings()
                        viewModel.triggerSync()
                        viewModel.updatePeriodicSync()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("退出登录", role: .destructive) {
                        viewModel.logout()
                    }

                    Spacer()

                    switch viewModel.syncEngine.status {
                    case .idle:
                        Text("未同步")
                            .foregroundStyle(.secondary)
                    case .syncing:
                        ProgressView()
                            .controlSize(.small)
                        Text("同步中...")
                            .foregroundStyle(.secondary)
                    case .success:
                        Text("✅ 已同步")
                            .foregroundStyle(.green)
                    case .error(let err):
                        Text("❌ 同步失败: \(err)")
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                VStack(alignment: .leading) {
                    Text("自动同步轮询间隔: \(Int(syncInterval)) 秒")
                    Slider(value: $syncInterval, in: 5...60, step: 5) { _ in
                        saveWebDAVSettings()
                        viewModel.updatePeriodicSync()
                    }
                }
            }

            Section("笔记存储") {
                LabeledContent("存储位置") {
                    Text(NotesViewModel.notesDirectory.path(percentEncoded: false))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("笔记以 .md 文件存储于 Application Support，Time Machine 会自动备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 400)
        .navigationTitle("设置")
        .onAppear { loadWebDAVSettings() }
    }

    @State private var webdavURL: String = ""
    @State private var webdavUsername: String = ""
    @State private var webdavPassword: String = ""
    @State private var syncInterval: Double = 30.0

    private func loadWebDAVSettings() {
        webdavURL = UserDefaults.standard.string(forKey: "webdavURL") ?? ""
        webdavUsername = UserDefaults.standard.string(forKey: "webdavUsername") ?? ""
        if !webdavUsername.isEmpty {
            webdavPassword = KeychainHelper.shared.readString(service: "JotWebDAV", account: webdavUsername) ?? ""
        }
        let interval = UserDefaults.standard.double(forKey: "syncInterval")
        syncInterval = interval >= 5 ? interval : 30.0
    }

    private func saveWebDAVSettings() {
        UserDefaults.standard.set(webdavURL, forKey: "webdavURL")
        UserDefaults.standard.set(syncInterval, forKey: "syncInterval")

        let oldUsername = UserDefaults.standard.string(forKey: "webdavUsername") ?? ""
        if oldUsername != webdavUsername && !oldUsername.isEmpty {
            KeychainHelper.shared.delete(service: "JotWebDAV", account: oldUsername)
        }

        UserDefaults.standard.set(webdavUsername, forKey: "webdavUsername")
        if !webdavPassword.isEmpty {
            KeychainHelper.shared.saveString(webdavPassword, service: "JotWebDAV", account: webdavUsername)
        }
    }
}
