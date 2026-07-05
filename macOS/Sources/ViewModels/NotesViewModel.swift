import SwiftUI
import Observation
import AppKit

/// Jot 应用核心 ViewModel
/// 笔记存储在 ~/Library/Application Support/Jot/ 下，无需用户选择目录
@MainActor
@Observable
final class NotesViewModel {

    // MARK: - 登录状态
    var isLoggedIn: Bool = UserDefaults.standard.bool(forKey: "isLoggedIn") {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: "isLoggedIn")
        }
    }

    // MARK: - 笔记列表状态

    /// 笔记列表
    var notes: [NoteItem] = []

    /// 当前选中的笔记
    var selectedNote: NoteItem? = nil {
        didSet {
            if let note = selectedNote {
                currentContent = FileService.readFile(at: note.url)
            } else {
                currentContent = ""
            }
            hasUnsavedChanges = false
        }
    }

    /// 当前编辑器内容
    var currentContent: String = "" {
        didSet {
            if currentContent != oldValue {
                hasUnsavedChanges = true
                scheduleSave()
            }
        }
    }

    /// 是否有未保存的修改
    var hasUnsavedChanges: Bool = false

    /// 同步引擎
    let syncEngine = SyncEngine()

    // MARK: - 内置笔记库目录

    /// 固定使用 ~/Library/Application Support/Jot/ 作为笔记库
    /// 优雅、标准、无需用户授权、Time Machine 自动备份
    static var notesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Jot", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - 私有属性

    private var saveTask: Task<Void, Never>?
    private var directoryMonitor: DispatchSourceFileSystemObject?
    private var monitoredFD: Int32 = -1

    @ObservationIgnored private var periodicSyncTask: Task<Void, Never>?

    // MARK: - 初始化

    init() {
        if isLoggedIn {
            setupStorageAndLoad()
        }
    }

    /// 登录成功后调用：建立本地文件夹并初次拉取笔记
    func setupStorageAndLoad() {
        // 访问 notesDirectory 会自动建目录
        _ = Self.notesDirectory
        loadNotes()
    }

    /// 安全登出，清理本地缓存和登录标记
    func logout() {
        isLoggedIn = false
        // 停止监听和定时同步
        stopWatching()
        stopPeriodicSync()
        // 清空内容
        notes.removeAll()
        selectedNote = nil
        currentContent = ""
        hasUnsavedChanges = false
    }

    deinit {
        periodicSyncTask?.cancel()
    }

    // MARK: - 笔记操作

    /// 加载笔记列表
    func loadNotes() {
        let directory = Self.notesDirectory

        notes = FileService.listMarkdownFiles(in: directory)

        // 如果当前选中的笔记被外部修改（同步拉取），刷新编辑器内容
        if let currentSelected = selectedNote,
           let updatedNote = notes.first(where: { $0.url == currentSelected.url }),
           updatedNote.modifiedDate > currentSelected.modifiedDate {
            selectedNote = updatedNote
        }

        startWatching(directory: directory)
        startPeriodicSync()
    }

    /// 选中一个笔记
    func selectNote(_ note: NoteItem?) {
        saveCurrentNoteIfNeeded()
        selectedNote = note
        if let note = note {
            currentContent = FileService.readFile(at: note.url)
        } else {
            currentContent = ""
        }
        hasUnsavedChanges = false
    }

    /// 创建新笔记
    func createNewNote() {
        let directory = Self.notesDirectory
        do {
            let fileURL = try FileService.createFile(in: directory)
            try FileService.writeFile(content: "新备忘录\n", to: fileURL)
            loadNotes()
            if let newNote = notes.first(where: { $0.url == fileURL }) {
                selectNote(newNote)
            }
        } catch {
            print("创建笔记失败: \(error)")
        }
    }

    /// 删除笔记
    func deleteNote(_ note: NoteItem) {
        do {
            try FileService.deleteFile(at: note.url)
            if selectedNote == note {
                selectedNote = nil
                currentContent = ""
                hasUnsavedChanges = false
            }
            loadNotes()
        } catch {
            print("删除笔记失败: \(error)")
        }
    }

    /// 保存当前笔记（如有修改）
    func saveCurrentNoteIfNeeded() {
        guard hasUnsavedChanges, let note = selectedNote else { return }
        do {
            try FileService.writeFile(content: currentContent, to: note.url)
            hasUnsavedChanges = false
            triggerSync()
        } catch {
            print("保存笔记失败: \(error)")
        }
    }

    // MARK: - 同步

    /// 触发 WebDAV 同步
    func triggerSync() {
        let directory = Self.notesDirectory

        var urlString = UserDefaults.standard.string(forKey: "webdavURL") ?? ""
        if !urlString.hasSuffix("/") { urlString += "/" }
        if !urlString.hasSuffix("Jot/") { urlString += "Jot/" }

        let username = UserDefaults.standard.string(forKey: "webdavUsername") ?? ""
        let password = KeychainHelper.shared.readString(service: "JotWebDAV", account: username) ?? ""

        guard let baseURL = URL(string: urlString), !username.isEmpty, !password.isEmpty else {
            syncEngine.status = .error("未配置完整的 WebDAV 账号或密码")
            return
        }

        let client = WebDAVClient(baseURL: baseURL, username: username, appPassword: password)

        Task {
            await syncEngine.startSync(directoryURL: directory, client: client)
            self.loadNotes()
        }
    }

    // MARK: - 周期性同步

    func updatePeriodicSync() {
        startPeriodicSync()
    }

    private func startPeriodicSync() {
        stopPeriodicSync()
        let interval = UserDefaults.standard.double(forKey: "syncInterval")
        let actualInterval = interval >= 5 ? interval : 30.0

        periodicSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(actualInterval))
                if Task.isCancelled { break }
                self?.triggerSync()
            }
        }
    }

    private func stopPeriodicSync() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
    }

    // MARK: - 延迟保存

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                saveCurrentNoteIfNeeded()
            }
        }
    }

    // MARK: - 目录监听

    private func startWatching(directory: URL) {
        stopWatching()
        monitoredFD = open(directory.path, O_EVTONLY)
        guard monitoredFD >= 0 else { return }

        directoryMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: monitoredFD,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        directoryMonitor?.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.loadNotes()
            }
        }
        directoryMonitor?.setCancelHandler { [weak self] in
            if let fd = self?.monitoredFD, fd >= 0 { close(fd) }
        }
        directoryMonitor?.resume()
    }

    private func stopWatching() {
        directoryMonitor?.cancel()
        directoryMonitor = nil
    }
}
