import Foundation

/// 简易原生 WebDAV 客户端
final class WebDAVClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let authString: String
    
    init(baseURL: URL, username: String, appPassword: String) {
        var stringURL = baseURL.absoluteString
        if !stringURL.hasSuffix("/") {
            stringURL += "/"
        }
        self.baseURL = URL(string: stringURL)!
        
        let loginString = "\(username):\(appPassword)"
        let loginData = loginString.data(using: .utf8)!
        self.authString = "Basic \(loginData.base64EncodedString())"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    private func makeRequest(for path: String, method: String) -> URLRequest {
        let url: URL
        if path.isEmpty {
            url = baseURL
        } else if path.hasPrefix("/") {
            // 绝对路径，比如从 href 获取到的
            // href 通常已经是 url-encoded 的，直接使用 string 拼接比较安全
            // 坚果云的 href 包含了 /dav/...
            let hostStr = "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")"
            url = URL(string: hostStr + path) ?? baseURL.appendingPathComponent(path)
        } else {
            // 相对路径（文件名），appendingPathComponent 会自动处理 URL 编码
            url = baseURL.appendingPathComponent(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authString, forHTTPHeaderField: "Authorization")
        return request
    }
    
    // MARK: - API
    
    /// 获取远程文件列表及其 ETag
    func listFiles(path: String = "") async throws -> [WebDAVFile] {
        var request = makeRequest(for: path, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.requestFailed(response, data)
        }
        
        return parsePropfindResponse(data: data)
    }
    
    /// 下载文件
    func download(path: String) async throws -> Data {
        let request = makeRequest(for: path, method: "GET")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.requestFailed(response, data)
        }
        return data
    }
    
    /// 上传文件，返回新生成的 ETag（如果有）
    func upload(path: String, data: Data) async throws -> String? {
        var request = makeRequest(for: path, method: "PUT")
        request.httpBody = data
        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.requestFailed(response, responseData)
        }
        
        let etag = httpResponse.allHeaderFields["Etag"] as? String ?? httpResponse.allHeaderFields["etag"] as? String
        return etag?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    
    /// 删除文件
    func delete(path: String) async throws {
        let request = makeRequest(for: path, method: "DELETE")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.requestFailed(response, data)
        }
    }
    
    /// 创建集合（目录）
    func mkcol(path: String) async throws {
        let request = makeRequest(for: path, method: "MKCOL")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.requestFailed(response, data)
        }
    }
    
    // MARK: - XML Parsing (Very basic)
    
    private func parsePropfindResponse(data: Data) -> [WebDAVFile] {
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        var files = [WebDAVFile]()
        
        // 由于不想引入复杂的 XML 解析库，这里使用正则提取 <d:response>
        let responseRegex = try! NSRegularExpression(pattern: "<[a-zA-Z0-9:]*response>([\\s\\S]*?)</[a-zA-Z0-9:]*response>", options: [])
        let matches = responseRegex.matches(in: xmlString, range: NSRange(location: 0, length: xmlString.utf16.count))
        
        for match in matches {
            guard let range = Range(match.range(at: 1), in: xmlString) else { continue }
            let responseStr = String(xmlString[range])
            
            // 提取 href
            let href = extractTagContent(from: responseStr, tag: "href") ?? ""
            guard href.hasSuffix(".md") else { continue } // 我们只关心 md 文件
            
            let name = URL(string: href)?.lastPathComponent ?? ""
            if name.isEmpty { continue }
            
            // 提取 ETag
            let etag = extractTagContent(from: responseStr, tag: "getetag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
            
            // 提取 LastModified
            let lastModifiedStr = extractTagContent(from: responseStr, tag: "getlastmodified") ?? ""
            
            files.append(WebDAVFile(name: name, href: href, eTag: etag, lastModifiedStr: lastModifiedStr))
        }
        
        return files
    }
    
    private func extractTagContent(from xml: String, tag: String) -> String? {
        // 匹配 <d:tag>content</d:tag> 或 <tag>content</tag>
        let regex = try! NSRegularExpression(pattern: "<(?:[a-zA-Z0-9]+:)?\(tag)>(.*?)</(?:[a-zA-Z0-9]+:)?\(tag)>", options: [])
        if let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: xml.utf16.count)) {
            if let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
            }
        }
        return nil
    }
}

struct WebDAVFile {
    let name: String
    let href: String
    let eTag: String
    let lastModifiedStr: String
}

enum WebDAVError: LocalizedError {
    case requestFailed(URLResponse?, Data?)
    
    var errorDescription: String? {
        switch self {
        case .requestFailed(let response, let data):
            var msg = "网络请求失败"
            if let httpResponse = response as? HTTPURLResponse {
                msg += " (HTTP \(httpResponse.statusCode))"
            }
            if let data = data, let bodyString = String(data: data, encoding: .utf8), !bodyString.isEmpty {
                msg += "\n服务器返回: \(bodyString)"
            }
            return msg
        }
    }
}
