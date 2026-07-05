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
    
    // MARK: - XML Parsing
    
    private func parsePropfindResponse(data: Data) -> [WebDAVFile] {
        let parser = WebDAVXMLParser()
        return parser.parse(data: data)
    }
}

final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    var files: [WebDAVFile] = []
    private var currentElement = ""
    private var currentHref = ""
    private var currentEtag = ""
    private var currentLastModified = ""
    private var inResponse = false
    
    func parse(data: Data) -> [WebDAVFile] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return files
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
        currentElement = name
        
        if name == "response" {
            inResponse = true
            currentHref = ""
            currentEtag = ""
            currentLastModified = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inResponse else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        
        if currentElement == "href" {
            currentHref += trimmed
        } else if currentElement == "getetag" {
            currentEtag += trimmed
        } else if currentElement == "getlastmodified" {
            currentLastModified += trimmed
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
        
        if name == "response" {
            if currentHref.hasSuffix(".md") {
                if let url = URL(string: currentHref) {
                    let fileName = url.lastPathComponent
                    if !fileName.isEmpty {
                        let etag = currentEtag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        files.append(WebDAVFile(name: fileName, href: currentHref, eTag: etag, lastModifiedStr: currentLastModified))
                    }
                }
            }
            inResponse = false
        }
        currentElement = ""
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
