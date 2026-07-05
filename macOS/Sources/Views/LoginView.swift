import SwiftUI

struct LoginView: View {
    @Environment(NotesViewModel.self) private var viewModel
    
    @State private var webdavURL = UserDefaults.standard.string(forKey: "webdavURL") ?? ""
    @State private var webdavUsername = UserDefaults.standard.string(forKey: "webdavUsername") ?? ""
    @State private var webdavPassword = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Welcome to Jot")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("极简、原生、属于你的备忘录")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WebDAV 服务器地址")
                        .font(.headline)
                    TextField("https://dav.jianguoyun.com/dav/", text: $webdavURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("WebDAV 账号")
                        .font(.headline)
                    TextField("例如: user@example.com", text: $webdavUsername)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("应用密码")
                        .font(.headline)
                    SecureField("输入应用专有密码", text: $webdavPassword)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoading)
                }
            }
            .frame(width: 320)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(width: 320)
            }
            
            Button(action: performLogin) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 100)
                } else {
                    Text("连接并登录")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading || webdavURL.isEmpty || webdavUsername.isEmpty || webdavPassword.isEmpty)
            .padding(.top, 10)
        }
        .frame(minWidth: 500, minHeight: 450)
        .onAppear {
            // 尝试读取钥匙串里的密码填入
            if let passStr = KeychainHelper.shared.readString(service: "JotWebDAV", account: webdavUsername) {
                webdavPassword = passStr
            }
        }
    }
    
    private func performLogin() {
        guard !webdavURL.isEmpty, !webdavUsername.isEmpty, !webdavPassword.isEmpty else {
            errorMessage = "请完整填写所有信息"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let baseUrl = webdavURL.hasSuffix("/") ? webdavURL : webdavURL + "/"
        let finalUrl = baseUrl + "Jot/"
        
        // 验证连接
        Task {
            do {
                guard let finalURL = URL(string: finalUrl) else {
                    throw URLError(.badURL)
                }
                let client = WebDAVClient(baseURL: finalURL, username: webdavUsername, appPassword: webdavPassword)
                // 尝试列出文件
                do {
                    _ = try await client.listFiles()
                } catch {
                    // 若目录不存在尝试创建
                    try await client.mkcol(path: "")
                    _ = try await client.listFiles()
                }
                
                // 验证成功，保存配置
                await MainActor.run {
                    UserDefaults.standard.set(baseUrl, forKey: "webdavURL")
                    UserDefaults.standard.set(webdavUsername, forKey: "webdavUsername")
                    
                    KeychainHelper.shared.saveString(webdavPassword, service: "JotWebDAV", account: webdavUsername)
                    
                    viewModel.isLoggedIn = true
                    viewModel.setupStorageAndLoad()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "验证失败: \(error.localizedDescription)"
                }
            }
        }
    }
}
