import Foundation

/// 文件系统操作服务
/// 负责 .md 文件的增删改查和目录监听
struct FileService: Sendable {
    
    /// 列举目录下所有 .md 文件，按修改时间降序排列
    static func listMarkdownFiles(in directory: URL) -> [NoteItem] {
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url -> NoteItem? in
                guard let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                ) else { return nil }
                
                let title = extractTitle(from: url)
                
                return NoteItem(
                    url: url,
                    title: title,
                    modifiedDate: values.contentModificationDate ?? Date.distantPast,
                    fileSize: Int64(values.fileSize ?? 0)
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }
    
    private static func extractTitle(from url: URL) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return "空备忘录" }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if trimmed.hasPrefix("#") {
                    let title = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                    return title.isEmpty ? "空备忘录" : title
                }
                return trimmed
            }
        }
        return "空备忘录"
    }
    
    /// 读取文件内容
    static func readFile(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    
    /// 写入文件内容
    static func writeFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// 在指定目录创建新的 .md 文件（使用 UUID 命名）
    static func createFile(in directory: URL) throws -> URL {
        let fileName = "\(UUID().uuidString).md"
        let fileURL = directory.appendingPathComponent(fileName)
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    /// 删除文件
    static func deleteFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
