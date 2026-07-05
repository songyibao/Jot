import Foundation

/// 笔记数据模型
struct NoteItem: Identifiable, Hashable {
    /// 使用文件 URL 作为唯一标识
    var id: URL { url }
    
    /// 文件完整路径
    let url: URL
    
    /// 文件名（不含扩展名），现在一般为 UUID
    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    /// 笔记展示标题（从文件内容第一行提取）
    let title: String
    
    /// 最后修改时间
    let modifiedDate: Date
    
    /// 文件大小（字节）
    let fileSize: Int64
    
    static func == (lhs: NoteItem, rhs: NoteItem) -> Bool {
        lhs.url == rhs.url && lhs.title == rhs.title && lhs.modifiedDate == rhs.modifiedDate
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
