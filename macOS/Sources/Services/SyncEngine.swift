import Foundation

struct FileSyncState: Codable {
    let eTag: String
    let localModifiedDate: Date
}

struct SyncState: Codable {
    var files: [String: FileSyncState] = [:]
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case error(String)
    case success
}

@MainActor
@Observable
class SyncEngine {
    var status: SyncStatus = .idle
    
    private let fileManager = FileManager.default
    private var syncState: SyncState = SyncState()
    
    init() {}
    
    private func syncStateURL(in directoryURL: URL) -> URL {
        return directoryURL.appendingPathComponent(".sync_state.json")
    }
    
    private func loadSyncState(in directoryURL: URL) {
        let url = syncStateURL(in: directoryURL)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            syncState = try JSONDecoder().decode(SyncState.self, from: data)
        } catch {
            print("读取同步状态失败: \(error)")
        }
    }
    
    private func saveSyncState(in directoryURL: URL) {
        let url = syncStateURL(in: directoryURL)
        do {
            let data = try JSONEncoder().encode(syncState)
            try data.write(to: url)
        } catch {
            print("保存同步状态失败: \(error)")
        }
    }
    
    enum NoteSyncState {
        case synced
        case pending
        case conflict
    }
    
    func fileSyncState(for fileURL: URL, localModifiedDate: Date) -> NoteSyncState {
        let name = fileURL.lastPathComponent
        if name.contains("_conflict_") {
            return .conflict
        }
        guard let state = syncState.files[name] else {
            print("SyncEngine [\(name)]: state is nil -> pending")
            return .pending // 尚未同步过
        }
        let diff = abs(localModifiedDate.timeIntervalSince(state.localModifiedDate))
        if diff > 1.0 {
            print("SyncEngine [\(name)]: local(\(localModifiedDate.timeIntervalSince1970)) != state(\(state.localModifiedDate.timeIntervalSince1970)), diff: \(diff) -> pending")
            return .pending // 本地已修改，等待同步
        }
        return .synced // 已同步
    }
    
    private var isSyncingGuard = false
    private var syncRequested = false
    
    func startSync(directoryURL: URL, client: WebDAVClient) async {
        if isSyncingGuard {
            syncRequested = true
            return
        }
        
        isSyncingGuard = true
        
        // 使用一个循环，只要在同步过程中有人再次请求同步，结束后就再跑一次
        repeat {
            syncRequested = false
            status = .syncing
            await performSync(directoryURL: directoryURL, client: client)
        } while syncRequested
        
        isSyncingGuard = false
    }
    
    private func performSync(directoryURL: URL, client: WebDAVClient) async {
        loadSyncState(in: directoryURL)
        
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { directoryURL.stopAccessingSecurityScopedResource() }
        }
        
        do {
            // 确保远端有一个存储笔记的文件夹
            var remoteFilesList = [WebDAVFile]()
            do {
                remoteFilesList = try await client.listFiles()
            } catch WebDAVError.requestFailed(let response, let data) {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 404 {
                    // 目录不存在，自动创建
                    try await client.mkcol(path: "")
                    remoteFilesList = try await client.listFiles()
                } else {
                    throw WebDAVError.requestFailed(response, data)
                }
            }
            
            var remoteFiles = [String: WebDAVFile]()
            for f in remoteFilesList {
                remoteFiles[f.name] = f
            }
            
            // 2. 获取本地列表
            let localFilesList = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            var localFiles = [String: URL]()
            var localModifiedDates = [String: Date]()
            
            for url in localFilesList {
                guard url.pathExtension == "md" else { continue }
                let name = url.lastPathComponent
                localFiles[name] = url
                if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                   let modDate = attrs[.modificationDate] as? Date {
                    localModifiedDates[name] = modDate
                }
            }
            
            var newSyncState = syncState
            
            // 3. 开始比对
            // 遍历所有云端文件
            for (name, remote) in remoteFiles {
                let localURL = directoryURL.appendingPathComponent(name)
                let hasLocal = localFiles[name] != nil
                let state = syncState.files[name]
                
                let remoteChanged = (state == nil) || (state!.eTag != remote.eTag)
                let localModDate = localModifiedDates[name]
                // 判断本地是否被修改过（稍微有些容差，1秒内认为没变）
                let localChanged = hasLocal && (state == nil || localModDate == nil || abs(localModDate!.timeIntervalSince(state!.localModifiedDate)) > 1.0)
                
                if hasLocal {
                    if remoteChanged && localChanged {
                        // 冲突：重命名本地文件为冲突文件并上传，然后下载远端文件
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyyMMdd_HHmmss"
                        let conflictName = name.replacingOccurrences(of: ".md", with: "_conflict_\(formatter.string(from: Date())).md")
                        let conflictURL = directoryURL.appendingPathComponent(conflictName)
                        
                        try fileManager.moveItem(at: localURL, to: conflictURL)
                        
                        // 上传冲突文件
                        let conflictData = try Data(contentsOf: conflictURL)
                        var conflictETag = try await client.upload(path: conflictName, data: conflictData)
                        if conflictETag == nil {
                            if let uploadedConflict = try await client.listFiles(path: conflictName).first {
                                conflictETag = uploadedConflict.eTag
                            }
                        }
                        // 将冲突文件加入下一次的同步记录，防止冲突套娃
                        if let conflictAttrs = try? fileManager.attributesOfItem(atPath: conflictURL.path),
                           let conflictModDate = conflictAttrs[.modificationDate] as? Date {
                            newSyncState.files[conflictName] = FileSyncState(eTag: conflictETag ?? "", localModifiedDate: conflictModDate)
                        }
                        
                        // 下载远端文件为主文件
                        let remoteData = try await client.download(path: remote.href)
                        try remoteData.write(to: localURL)
                        
                        // 更新主文件状态
                        if let newAttrs = try? fileManager.attributesOfItem(atPath: localURL.path),
                           let newModDate = newAttrs[.modificationDate] as? Date {
                            newSyncState.files[name] = FileSyncState(eTag: remote.eTag, localModifiedDate: newModDate)
                        }
                    } else if remoteChanged {
                        // 远端变了，本地没变：下载
                        let remoteData = try await client.download(path: remote.href)
                        try remoteData.write(to: localURL)
                        if let newAttrs = try? fileManager.attributesOfItem(atPath: localURL.path),
                           let newModDate = newAttrs[.modificationDate] as? Date {
                            newSyncState.files[name] = FileSyncState(eTag: remote.eTag, localModifiedDate: newModDate)
                        }
                    } else if localChanged {
                        // 本地变了，远端没变：上传
                        let localData = try Data(contentsOf: localURL)
                        var newETag = try await client.upload(path: name, data: localData)
                        
                        // 如果 PUT 响应头里没有返回 ETag，手动拉取一次（极其重要，否则下次会视为远端更新导致冲突）
                        if newETag == nil {
                            if let uploadedFile = try await client.listFiles(path: name).first {
                                newETag = uploadedFile.eTag
                            }
                        }
                        
                        newSyncState.files[name] = FileSyncState(eTag: newETag ?? "", localModifiedDate: localModDate!)
                    } else {
                        // 两边都没变，保持
                        newSyncState.files[name] = state
                    }
                } else {
                    if state != nil {
                        // 本地有记录，但本地文件不在了，说明本地删除了
                        // 删除远端
                        try await client.delete(path: remote.href)
                        newSyncState.files.removeValue(forKey: name)
                    } else {
                        // 本地没记录，说明是远端新增的
                        // 下载
                        let remoteData = try await client.download(path: remote.href)
                        try remoteData.write(to: localURL)
                        if let newAttrs = try? fileManager.attributesOfItem(atPath: localURL.path),
                           let newModDate = newAttrs[.modificationDate] as? Date {
                            newSyncState.files[name] = FileSyncState(eTag: remote.eTag, localModifiedDate: newModDate)
                        }
                    }
                }
            }
            
            // 遍历所有本地文件
            for (name, localURL) in localFiles {
                if remoteFiles[name] != nil { continue } // 已经在上面处理过了
                
                let state = syncState.files[name]
                if state != nil {
                    // 远端没有，本地有记录，说明远端被删除了
                    // 删除本地
                    try fileManager.removeItem(at: localURL)
                    newSyncState.files.removeValue(forKey: name)
                } else {
                    // 本地有，远端没有，本地无记录，说明本地新增
                    // 上传
                    let localData = try Data(contentsOf: localURL)
                    var newETag = try await client.upload(path: name, data: localData)
                    
                    if newETag == nil {
                        if let uploadedFile = try await client.listFiles(path: name).first {
                            newETag = uploadedFile.eTag
                        }
                    }
                    
                    if let modDate = localModifiedDates[name] {
                        newSyncState.files[name] = FileSyncState(eTag: newETag ?? "", localModifiedDate: modDate)
                    }
                }
            }
            
            // 保存新的同步状态
            self.syncState = newSyncState
            saveSyncState(in: directoryURL)
            
            status = .success
        } catch {
            print("同步失败: \(error)")
            status = .error(error.localizedDescription)
        }
    }
}
