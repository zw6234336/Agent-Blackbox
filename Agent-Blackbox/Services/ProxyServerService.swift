import Foundation
import Network
import Combine

struct ProxyRequestLog: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let client: String
    var model: String?
    var prompt: String?
    var response: String?
    var statusCode: Int?
    var duration: TimeInterval?
    var promptTokens: Int?
    var completionTokens: Int?
    var errorMessage: String?
    var isPending: Bool
}

@MainActor
final class ProxyServerService: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var port: Int = 9999
    @Published var capturedCount: Int = 0
    @Published var liveRequests: [ProxyRequestLog] = []

    private var listener: NWListener?
    private weak var database: DatabaseService?
    private weak var configService: ConfigService?
    
    private var activeConnections: [NWConnection] = []
    private let proxyQueue = DispatchQueue(label: "com.agent.blackbox.proxy", qos: .userInitiated)

    func bind(database: DatabaseService, config: ConfigService) {
        self.database = database
        self.configService = config
        self.port = config.config.proxyPort
    }

    func clearLiveRequests() {
        self.liveRequests.removeAll()
    }

    func start() {
        guard !isRunning else { return }
        
        let portToUse = configService?.config.proxyPort ?? 9999
        self.port = portToUse

        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: UInt16(portToUse))!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        Logger.shared.info("本地 AI 网关已启动，监听端口: \(portToUse)")
                    case .failed(let error):
                        self?.isRunning = false
                        Logger.shared.error("本地 AI 网关启动失败: \(error.localizedDescription)")
                    case .cancelled:
                        self?.isRunning = false
                        Logger.shared.info("本地 AI 网关已关闭")
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }
            
            listener?.start(queue: proxyQueue)
            
        } catch {
            Logger.shared.error("创建监听器失败: \(error.localizedDescription)")
            self.isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        listener?.cancel()
        listener = nil
        
        // Cancel all active connections
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        isRunning = false
    }

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in
                    self?.activeConnections.removeAll(where: { $0 === connection })
                }
            }
        }
        
        connection.start(queue: proxyQueue)
        readRequest(connection: connection)
    }

    // MARK: - HTTP Request Parsing

    private func readRequest(connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    Logger.shared.error("网关读取请求数据失败: \(error.localizedDescription)")
                    connection.cancel()
                    return
                }
                
                var newBuffer = buffer
                if let content = content {
                    newBuffer.append(content)
                }
                
                // Check if we have received the headers yet
                if let headersEndRange = newBuffer.range(of: Data("\r\n\r\n".utf8)) {
                    let headersData = newBuffer.subdata(in: 0..<headersEndRange.lowerBound)
                    let bodyData = newBuffer.subdata(in: headersEndRange.upperBound..<newBuffer.count)
                    
                    if let headersStr = String(data: headersData, encoding: .utf8) {
                        self.processRequest(connection: connection, headersStr: headersStr, bodyData: bodyData)
                    } else {
                        Logger.shared.error("网关请求头编码异常")
                        self.sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", headers: [:], body: Data("Invalid headers encoding".utf8))
                    }
                } else {
                    if isComplete {
                        connection.cancel()
                    } else {
                        self.readRequest(connection: connection, buffer: newBuffer)
                    }
                }
            }
        }
    }

    private func processRequest(connection: NWConnection, headersStr: String, bodyData: Data) {
        let headerLines = headersStr.components(separatedBy: "\r\n")
        guard !headerLines.isEmpty else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", headers: [:], body: Data("Empty Request".utf8))
            return
        }
        
        // Parse Request Line (e.g. "POST /v1/chat/completions HTTP/1.1")
        let requestLineParts = headerLines[0].components(separatedBy: " ")
        guard requestLineParts.count >= 2 else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", headers: [:], body: Data("Invalid Request Line".utf8))
            return
        }
        let method = requestLineParts[0]
        let path = requestLineParts[1]
        
        // Parse Headers
        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                headers[key] = value
            }
        }
        
        // Check Content-Length to see if we have read the whole body
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if bodyData.count < contentLength {
            // Need to read more body data
            readRemainingBody(connection: connection, headersStr: headersStr, method: method, path: path, headers: headers, contentLength: contentLength, bodyData: bodyData)
        } else {
            // We have the complete body!
            handleCompleteRequest(connection: connection, method: method, path: path, headers: headers, body: bodyData.prefix(contentLength))
        }
    }

    private func readRemainingBody(connection: NWConnection, headersStr: String, method: String, path: String, headers: [String: String], contentLength: Int, bodyData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    Logger.shared.error("读取请求体失败: \(error.localizedDescription)")
                    connection.cancel()
                    return
                }
                
                var newBodyData = bodyData
                if let content = content {
                    newBodyData.append(content)
                }
                
                if newBodyData.count >= contentLength {
                    self.handleCompleteRequest(connection: connection, method: method, path: path, headers: headers, body: newBodyData.prefix(contentLength))
                } else if isComplete {
                    connection.cancel()
                } else {
                    self.readRemainingBody(connection: connection, headersStr: headersStr, method: method, path: path, headers: headers, contentLength: contentLength, bodyData: newBodyData)
                }
            }
        }
    }

    // MARK: - Request Forwarding

    private func resolveUpstreamBaseURL(path: String, headers: [String: String], body: Data) -> String {
        guard let config = configService?.config else {
            return "https://api.openai.com"
        }
        
        // 1. Check custom headers for explicit target base URL (lowest latency control)
        let customHeadersKeys = ["x-upstream-url", "x-base-url", "x-target-url", "openai-base-url"]
        for key in customHeadersKeys {
            if let customUrl = headers[key], !customUrl.isEmpty {
                Logger.shared.info("网关代理: 发现自定义目标上游 URL: \(PlanDetectionService.sanitizeURL(customUrl))")
                return customUrl
            }
        }
        
        // 2. Check Authorization or X-API-Key header prefix to guess provider
        let token: String? = {
            if let auth = headers["authorization"] {
                return auth.replacingOccurrences(of: "Bearer ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let xKey = headers["x-api-key"] {
                return xKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }()
        
        if let token = token {
            if token.hasPrefix("sk-or-") {
                Logger.shared.info("网关代理: 检测到 OpenRouter Token，重定向至 OpenRouter 上游")
                return "https://openrouter.ai/api"
            }
            if token.hasPrefix("sk-ant-") {
                Logger.shared.info("网关代理: 检测到 Anthropic Token，重定向至 Anthropic 上游")
                return "https://api.anthropic.com"
            }
        }
        
        // 3. Inspect JSON body to check requested model
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let model = json["model"] as? String {
            
            let modelLower = model.lowercased()
            let isLocalModel = modelLower.contains("gguf") ||
                               modelLower.contains("mlx") ||
                               modelLower.contains("local") ||
                               (modelLower.contains("/") && !modelLower.hasPrefix("ft:"))
            
            if isLocalModel {
                if modelLower.contains("ollama") {
                    Logger.shared.info("网关代理: 检测到 Ollama 模型 \(model)，自动路由至本地 Ollama 默认服务")
                    return "http://127.0.0.1:11434"
                } else {
                    let customUpstream = config.openaiUpstreamUrl
                    if customUpstream.contains("api.openai.com") {
                        Logger.shared.info("网关代理: 检测到本地模型 \(model)，自动路由至本地通用模型服务 (LM Studio/MLX)")
                        return "http://127.0.0.1:1234"
                    } else {
                        Logger.shared.info("网关代理: 检测到本地模型 \(model)，使用配置的自定义上游: \(PlanDetectionService.sanitizeURL(customUpstream))")
                        return customUpstream
                    }
                }
            }
            
            if !isLocalModel {
                if modelLower.contains("deepseek") {
                    Logger.shared.info("网关代理: 检测到 DeepSeek 模型 \(model)，自动路由至 DeepSeek 官方 API")
                    return "https://api.deepseek.com"
                }
                if modelLower.contains("gemini") {
                    Logger.shared.info("网关代理: 检测到 Gemini 模型 \(model)，自动路由至 Google Gemini 官方 API")
                    return "https://generativelanguage.googleapis.com/v1beta/openai"
                }
                if modelLower.contains("qwen") {
                    Logger.shared.info("网关代理: 检测到 Qwen 模型 \(model)，自动路由至阿里 DashScope API")
                    return "https://dashscope.aliyuncs.com"
                }
                if modelLower.contains("glm-") || modelLower.contains("zhipu") {
                    Logger.shared.info("网关代理: 检测到智谱 GLM 模型 \(model)，自动路由至智谱清言 API")
                    return "https://open.bigmodel.cn/api/paas/v4"
                }
            }
        }
        
        // 4. Default Fallback based on path
        if path.contains("messages") {
            return config.anthropicUpstreamUrl
        } else {
            return config.openaiUpstreamUrl
        }
    }

    private func handleCompleteRequest(connection: NWConnection, method: String, path: String, headers: [String: String], body: Data) {
        guard configService?.config != nil else {
            sendHTTPResponse(connection: connection, statusCode: 500, statusText: "Internal Error", headers: [:], body: Data("Missing configuration".utf8))
            return
        }

        // Determine Upstream URL dynamically
        let isAnthropic = path.contains("messages")
        let upstreamBase = resolveUpstreamBaseURL(path: path, headers: headers, body: body)
        let cleanBase = upstreamBase.hasSuffix("/") ? String(upstreamBase.dropLast()) : upstreamBase
        var cleanPath = path.hasPrefix("/") ? path : "/\(path)"
        
        // For Gemini or Zhipu (bigmodel.cn/v4) rewrite "/v1/chat/completions" to "/chat/completions"
        if cleanBase.contains("generativelanguage.googleapis.com") || 
           cleanBase.contains("bigmodel.cn") || 
           cleanBase.contains("/v4") {
            if cleanPath.hasPrefix("/v1/") {
                cleanPath = String(cleanPath.dropFirst(3)) // "/v1/chat/completions" -> "/chat/completions"
            }
        }
        
        // For Anthropic, ensure the path has "/v1" prefix
        if cleanBase.contains("api.anthropic.com") {
            if !cleanPath.hasPrefix("/v1/") {
                cleanPath = "/v1" + cleanPath // "/messages" -> "/v1/messages"
            }
        }
        
        guard var comps = URLComponents(string: cleanBase) else {
            sendHTTPResponse(connection: connection, statusCode: 500, statusText: "Internal Error", headers: [:], body: Data("Invalid Upstream URL".utf8))
            return
        }
        
        let pathQueryParts = cleanPath.components(separatedBy: "?")
        let rawPath = pathQueryParts[0]
        
        let baseHasTrailingSlash = cleanBase.hasSuffix("/")
        let pathHasLeadingSlash = rawPath.hasPrefix("/")
        
        var combinedPath = comps.path
        if baseHasTrailingSlash && pathHasLeadingSlash {
            combinedPath += String(rawPath.dropFirst())
        } else if !baseHasTrailingSlash && !pathHasLeadingSlash {
            combinedPath += "/" + rawPath
        } else {
            combinedPath += rawPath
        }
        
        comps.path = combinedPath
        
        if pathQueryParts.count > 1 {
            comps.query = pathQueryParts[1]
        }
        
        guard let upstreamURL = comps.url else {
            sendHTTPResponse(connection: connection, statusCode: 500, statusText: "Internal Error", headers: [:], body: Data("Invalid Upstream URL".utf8))
            return
        }

        // Detect downstream client from headers
        var client = "unknown"
        if let clientIdentifier = headers["x-client-identifier"]?.lowercased() {
            client = clientIdentifier
        } else if let ua = headers["user-agent"]?.lowercased() {
            if ua.contains("cline") || ua.contains("claude-dev") || ua.contains("roo-cline") {
                client = "cline"
            } else if ua.contains("cursor") || ua.contains("vscodium") {
                client = "cursor"
            } else if ua.contains("copilot") || ua.contains("github-copilot") {
                client = "copilot"
            } else if ua.contains("warp") {
                client = "warp"
            } else if ua.contains("claude-code") || ua.contains("claude-cli") {
                client = "claude-code"
            } else if ua.contains("pi") {
                client = "pi"
            } else if ua.contains("antigravity") {
                client = "antigravity"
            } else if ua.contains("python") || ua.contains("requests") || ua.contains("aiohttp") || ua.contains("urllib") {
                client = "python"
            } else if ua.contains("node") || ua.contains("axios") || ua.contains("node-fetch") {
                client = "node"
            } else if ua.contains("curl") {
                client = "curl"
            }
        } else if let referer = headers["referer"]?.lowercased() {
            if referer.contains("vscode-extension") {
                client = "vscode"
            }
        }

        // Parse Model & Prompt from Request Body
        let reqData = parseRequestBody(body)
        let startTime = Date()
        let requestId = UUID()

        // Insert into live requests list
        let newLog = ProxyRequestLog(
            id: requestId,
            timestamp: startTime,
            method: method,
            path: path,
            client: client,
            model: reqData.model,
            prompt: reqData.prompt,
            response: nil,
            statusCode: nil,
            duration: nil,
            promptTokens: nil,
            completionTokens: nil,
            errorMessage: nil,
            isPending: true
        )
        self.liveRequests.insert(newLog, at: 0)
        if self.liveRequests.count > 100 {
            self.liveRequests.removeLast()
        }

        // Create Outbound Request
        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = method
        upstreamRequest.httpBody = body
        
        // Copy Headers
        for (key, val) in headers {
            if key != "host" && key != "content-length" && key != "connection" {
                upstreamRequest.setValue(val, forHTTPHeaderField: key)
            }
        }

        // Send to real API
        let delegate = ProxySessionDelegate(connection: connection) { [weak self] httpResponse, responseData, isStreamingResponse, error in
            Task { @MainActor in
                self?.capturedCount += 1
                let duration = Date().timeIntervalSince(startTime)
                let statusCode = httpResponse?.statusCode ?? 500
                
                self?.logAndSaveRequest(
                    requestId: requestId,
                    startTime: startTime,
                    client: client,
                    path: path,
                    isAnthropic: isAnthropic,
                    isStreamingResponse: isStreamingResponse,
                    reqData: reqData,
                    respData: responseData,
                    statusCode: statusCode,
                    duration: duration,
                    error: error
                )
            }
        }
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: upstreamRequest)
        task.resume()
    }

    private func logAndSaveRequest(
        requestId: UUID,
        startTime: Date,
        client: String,
        path: String,
        isAnthropic: Bool,
        isStreamingResponse: Bool,
        reqData: RequestData,
        respData: Data,
        statusCode: Int,
        duration: TimeInterval,
        error: Error?
    ) {
        // Parse response content and tokens
        let isStreaming = isStreamingResponse
        
        let parsedResp: ResponseData
        if isStreaming {
            parsedResp = parseSSEStream(respData, isAnthropic: isAnthropic)
        } else {
            parsedResp = parseResponseBody(respData, isAnthropic: isAnthropic)
        }

        let model = reqData.model ?? parsedResp.modelOverride ?? "unknown"
        let prompt = reqData.prompt
        let responseText = parsedResp.text
        
        // Determine token counts (with estimation fallback)
        var promptTokensVal = parsedResp.promptTokens
        var completionTokensVal = parsedResp.completionTokens
        
        if (promptTokensVal == nil || completionTokensVal == nil), statusCode == 200 {
            if let pText = prompt {
                promptTokensVal = estimateTokens(for: pText)
            }
            if let rText = responseText {
                completionTokensVal = estimateTokens(for: rText)
            }
        }
        
        let totalTokensVal = (promptTokensVal != nil || completionTokensVal != nil) ? ((promptTokensVal ?? 0) + (completionTokensVal ?? 0)) : nil
        let errorMessage = error?.localizedDescription ?? (statusCode >= 400 ? "HTTP Error \(statusCode)" : nil)

        // Update live requests list
        if let index = self.liveRequests.firstIndex(where: { $0.id == requestId }) {
            self.liveRequests[index].isPending = false
            self.liveRequests[index].statusCode = statusCode
            self.liveRequests[index].duration = duration
            self.liveRequests[index].promptTokens = promptTokensVal
            self.liveRequests[index].completionTokens = completionTokensVal
            self.liveRequests[index].response = responseText
            self.liveRequests[index].errorMessage = errorMessage
            if model != "unknown" {
                self.liveRequests[index].model = model
            }
        } else {
            let newLog = ProxyRequestLog(
                id: requestId,
                timestamp: startTime,
                method: "POST",
                path: path,
                client: client,
                model: model,
                prompt: prompt,
                response: responseText,
                statusCode: statusCode,
                duration: duration,
                promptTokens: promptTokensVal,
                completionTokens: completionTokensVal,
                errorMessage: errorMessage,
                isPending: false
            )
            self.liveRequests.insert(newLog, at: 0)
            if self.liveRequests.count > 100 {
                self.liveRequests.removeLast()
            }
        }

        // Classify Provider based on path and model name keywords
        let provider: LLMProvider
        let modelLower = model.lowercased()
        let isLocalModel = modelLower.contains("gguf") ||
                           modelLower.contains("mlx") ||
                           modelLower.contains("local") ||
                           (modelLower.contains("/") && !modelLower.hasPrefix("ft:"))
        
        if isLocalModel {
            if modelLower.contains("ollama") {
                provider = .ollama
            } else {
                provider = .lmstudio
            }
        } else if isAnthropic || modelLower.contains("claude") || modelLower.contains("anthropic") {
            provider = .anthropic
        } else if modelLower.contains("gpt") || modelLower.contains("o1") || modelLower.contains("o3") {
            provider = .openai
        } else if modelLower.contains("gemini") {
            provider = .google
        } else if modelLower.contains("deepseek") {
            provider = .deepseek
        } else if modelLower.contains("qwen") {
            provider = .qwen
        } else if modelLower.contains("ollama") {
            provider = .ollama
        } else if modelLower.contains("kimi") || modelLower.contains("moonshot") {
            provider = .kimi
        } else if modelLower.contains("glm") || modelLower.contains("zhipu") {
            provider = .zhipu
        } else if modelLower.contains("inflection") || modelLower == "pi" || modelLower.contains("pi-") || modelLower.hasSuffix("-pi") {
            provider = .pi
        } else {
            provider = .custom
        }

        let sanitizedPrompt = Self.maskAPIKey(prompt)
        let sanitizedResponse = Self.maskAPIKey(responseText)
        let sanitizedError = Self.maskAPIKey(errorMessage)

        let parsedLog = ParsedLog(
            timestamp: startTime,
            sourceFile: "ProxyGateway",
            provider: provider,
            modelName: model,
            prompt: sanitizedPrompt,
            response: sanitizedResponse,
            promptTokens: promptTokensVal,
            completionTokens: completionTokensVal,
            totalTokens: totalTokensVal,
            duration: duration,
            statusCode: statusCode,
            errorMessage: sanitizedError,
            conversationId: nil,
            metadata: [
                "client": client,
                "mode": isStreaming ? "streaming" : "non-streaming",
                "url": path,
                "intercepted": "true"
            ]
        )

        Task {
            await database?.saveLog(parsedLog)
        }
    }



    // MARK: - Sensitive Data Masking

    /// 清洗 prompt/response/error 中可能嵌入的 API Key
    /// 防止明文 Key 写入 SQLite 数据库
    private static func maskAPIKey(_ text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"\b(sk|rk|api|key|token)-[A-Za-z0-9_\-]{8,}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        var masked = text
        for match in matches {
            let full = ns.substring(with: match.range)
            let prefix = full.prefix(5)
            let replacement = "\(prefix)***"
            if let range = Range(match.range, in: masked) {
                masked.replaceSubrange(range, with: replacement)
            }
        }
        return masked
    }

    private func estimateTokens(for text: String) -> Int {
        let chineseCharCount = text.filter { $0.isChineseCharacter }.count
        let otherCharCount = text.count - chineseCharCount
        return Int(Double(chineseCharCount) * 1.5 + Double(otherCharCount) / 4.0)
    }

    // MARK: - HTTP Helpers

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, statusText: String, headers: [String: String], body: Data) {
        var responseString = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        var clientHeaders = headers
        clientHeaders["Content-Length"] = String(body.count)
        clientHeaders["Connection"] = "close"
        
        for (key, val) in clientHeaders {
            responseString += "\(key): \(val)\r\n"
        }
        responseString += "\r\n"
        
        var responseData = responseString.data(using: .utf8) ?? Data()
        responseData.append(body)
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

// MARK: - URLSessionDataDelegate Wrapper

private class ProxySessionDelegate: NSObject, URLSessionDataDelegate {
    let clientConnection: NWConnection
    var responseHeadersSent = false
    var responseData = Data()
    var isStreamingResponse = false
    let onResponseComplete: (HTTPURLResponse?, Data, Bool, Error?) -> Void
    
    init(connection: NWConnection, onResponseComplete: @escaping (HTTPURLResponse?, Data, Bool, Error?) -> Void) {
        self.clientConnection = connection
        self.onResponseComplete = onResponseComplete
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        
        var clientHeaders: [String: String] = [:]
        for (key, val) in httpResponse.allHeaderFields {
            if let keyStr = key as? String {
                clientHeaders[keyStr] = val as? String
            }
        }
        
        // If streaming, ensure Transfer-Encoding is chunked
        isStreamingResponse = clientHeaders["content-type"]?.contains("text/event-stream") ?? false || 
                              clientHeaders["Content-Type"]?.contains("text/event-stream") ?? false
        
        if isStreamingResponse {
            clientHeaders["Transfer-Encoding"] = "chunked"
            clientHeaders.removeValue(forKey: "Content-Length")
            clientHeaders.removeValue(forKey: "content-length")
            
            sendResponseHeaders(connection: clientConnection, statusCode: httpResponse.statusCode, statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode), headers: clientHeaders)
            responseHeadersSent = true
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
        
        if isStreamingResponse && responseHeadersSent {
            sendChunk(connection: clientConnection, data: data)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let httpResponse = task.response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? (error == nil ? 200 : 500)
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        
        if !responseHeadersSent {
            var clientHeaders: [String: String] = [:]
            if let httpResponse = httpResponse {
                for (key, val) in httpResponse.allHeaderFields {
                    if let keyStr = key as? String {
                        clientHeaders[keyStr] = val as? String
                    }
                }
            }
            // Set correct content-length for non-streaming response
            clientHeaders["Content-Length"] = "\(responseData.count)"
            clientHeaders.removeValue(forKey: "content-length")
            clientHeaders.removeValue(forKey: "Transfer-Encoding")
            clientHeaders.removeValue(forKey: "transfer-encoding")
            
            sendResponseHeaders(connection: clientConnection, statusCode: statusCode, statusText: statusText, headers: clientHeaders)
            responseHeadersSent = true
            
            // Send raw data body
            if !responseData.isEmpty {
                let conn = clientConnection
                clientConnection.send(content: responseData, completion: .contentProcessed({ _ in
                    conn.cancel()
                }))
            } else {
                clientConnection.cancel()
            }
        } else {
            if isStreamingResponse {
                sendChunkEnd(connection: clientConnection)
            } else {
                clientConnection.cancel()
            }
        }
        
        onResponseComplete(httpResponse, responseData, isStreamingResponse, error)
        session.finishTasksAndInvalidate()
    }
    
    private func sendResponseHeaders(connection: NWConnection, statusCode: Int, statusText: String, headers: [String: String]) {
        var responseString = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (key, val) in headers {
            if key.lowercased() != "connection" {
                responseString += "\(key): \(val)\r\n"
            }
        }
        responseString += "Connection: keep-alive\r\n\r\n"
        connection.send(content: responseString.data(using: .utf8), completion: .contentProcessed({ _ in }))
    }
    
    private func sendChunk(connection: NWConnection, data: Data) {
        guard !data.isEmpty else { return }
        let hexSize = String(data.count, radix: 16)
        var chunk = Data()
        chunk.append(contentsOf: "\(hexSize)\r\n".utf8)
        chunk.append(data)
        chunk.append(contentsOf: "\r\n".utf8)
        connection.send(content: chunk, completion: .contentProcessed({ _ in }))
    }
    
    private func sendChunkEnd(connection: NWConnection) {
        connection.send(content: "0\r\n\r\n".data(using: .utf8)!, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

// MARK: - JSON Extraction Helpers

private struct RequestData {
    let model: String?
    let prompt: String?
}

private func parseRequestBody(_ data: Data) -> RequestData {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return RequestData(model: nil, prompt: nil)
    }
    
    let model = json["model"] as? String
    
    // Try OpenAI format
    if let messages = json["messages"] as? [[String: Any]] {
        let prompt = messages.compactMap { msg -> String? in
            let role = msg["role"] as? String ?? ""
            let content = msg["content"]
            let contentStr: String
            if let str = content as? String {
                contentStr = str
            } else if let arr = content as? [[String: Any]] {
                contentStr = arr.compactMap { item -> String? in
                    if item["type"] as? String == "text" {
                        return item["text"] as? String
                    }
                    return nil
                }.joined(separator: "\n")
            } else {
                return nil
            }
            return "\(role.uppercased()): \(contentStr)"
        }.joined(separator: "\n")
        
        return RequestData(model: model, prompt: prompt)
    }
    
    // Try Anthropic format
    if let system = json["system"] as? String, let messages = json["messages"] as? [[String: Any]] {
        var parts: [String] = []
        if !system.isEmpty {
            parts.append("SYSTEM: \(system)")
        }
        for msg in messages {
            let role = msg["role"] as? String ?? ""
            let content = msg["content"]
            let contentStr: String
            if let str = content as? String {
                contentStr = str
            } else if let arr = content as? [[String: Any]] {
                contentStr = arr.compactMap { item -> String? in
                    if item["type"] as? String == "text" {
                        return item["text"] as? String
                    }
                    return nil
                }.joined(separator: "\n")
            } else {
                continue
            }
            parts.append("\(role.uppercased()): \(contentStr)")
        }
        return RequestData(model: model, prompt: parts.joined(separator: "\n"))
    }
    
    // Try OpenAI text completions format (prompt is a String or Array of Strings)
    if let prompt = json["prompt"] as? String {
        return RequestData(model: model, prompt: prompt)
    } else if let promptArray = json["prompt"] as? [String] {
        return RequestData(model: model, prompt: promptArray.joined(separator: "\n"))
    }
    
    return RequestData(model: model, prompt: nil)
}

private struct ResponseData {
    let text: String?
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let modelOverride: String?
}

private func parseResponseBody(_ data: Data, isAnthropic: Bool) -> ResponseData {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return ResponseData(text: nil, promptTokens: nil, completionTokens: nil, totalTokens: nil, modelOverride: nil)
    }
    
    let modelOverride = json["model"] as? String
    
    if isAnthropic {
        let contentArr = json["content"] as? [[String: Any]]
        let text = contentArr?.compactMap { block -> String? in
            if block["type"] as? String == "text" {
                return block["text"] as? String
            }
            return nil
        }.joined(separator: "\n")
        
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int
        let outputTokens = usage?["output_tokens"] as? Int
        let total = (inputTokens != nil || outputTokens != nil) ? ((inputTokens ?? 0) + (outputTokens ?? 0)) : nil
        return ResponseData(text: text, promptTokens: inputTokens, completionTokens: outputTokens, totalTokens: total, modelOverride: modelOverride)
    } else {
        // OpenAI format (chat completions message vs text completions text)
        let choices = json["choices"] as? [[String: Any]]
        let firstChoice = choices?.first
        let text: String?
        if let message = firstChoice?["message"] as? [String: Any] {
            text = message["content"] as? String
        } else {
            text = firstChoice?["text"] as? String
        }
        
        let usage = json["usage"] as? [String: Any]
        let promptTokens = usage?["prompt_tokens"] as? Int
        let completionTokens = usage?["completion_tokens"] as? Int
        let totalTokens = usage?["total_tokens"] as? Int
        
        return ResponseData(text: text, promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens, modelOverride: modelOverride)
    }
}

private func parseSSEStream(_ data: Data, isAnthropic: Bool) -> ResponseData {
    guard let streamStr = String(data: data, encoding: .utf8) else {
        return ResponseData(text: nil, promptTokens: nil, completionTokens: nil, totalTokens: nil, modelOverride: nil)
    }
    
    var assistantText = ""
    var promptTokens: Int? = nil
    var completionTokens: Int? = nil
    var modelOverride: String? = nil
    
    let lines = streamStr.components(separatedBy: "\n")
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // OpenAI format chunk starts with "data: "
        // Anthropic chunk starts with "data: " too
        guard trimmed.hasPrefix("data:") else { continue }
        
        let jsonStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr == "[DONE]" { continue }
        
        guard let chunkData = jsonStr.data(using: .utf8),
              let chunkJSON = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any] else {
            continue
        }
        
        if let model = chunkJSON["model"] as? String {
            modelOverride = model
        }
        
        if isAnthropic {
            let type = chunkJSON["type"] as? String ?? ""
            if type == "message_start" {
                if let message = chunkJSON["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    promptTokens = usage["input_tokens"] as? Int
                }
            } else if type == "content_block_delta" {
                if let delta = chunkJSON["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    assistantText += text
                }
            } else if type == "message_delta" {
                if let usage = chunkJSON["usage"] as? [String: Any] {
                    completionTokens = usage["output_tokens"] as? Int
                }
            }
        } else {
            // OpenAI format (chat completion delta vs text completion text)
            if let choices = chunkJSON["choices"] as? [[String: Any]],
               let first = choices.first {
                if let delta = first["delta"] as? [String: Any] {
                    if let text = delta["content"] as? String {
                        assistantText += text
                    }
                } else if let text = first["text"] as? String {
                    assistantText += text
                }
            }
            
            // Check for usage in chunk (OpenAI style)
            if let usage = chunkJSON["usage"] as? [String: Any] {
                promptTokens = usage["prompt_tokens"] as? Int
                completionTokens = usage["completion_tokens"] as? Int
            }
        }
    }
    
    let textResult = assistantText.isEmpty ? nil : assistantText
    let total = (promptTokens != nil || completionTokens != nil) ? ((promptTokens ?? 0) + (completionTokens ?? 0)) : nil
    return ResponseData(text: textResult, promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: total, modelOverride: modelOverride)
}

// MARK: - Character Extension for Chinese Detection

extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }
}
