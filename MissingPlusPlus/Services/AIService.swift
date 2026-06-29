import Foundation

/// OpenAI 兼容协议的轻量客户端。Settings 里配 base-url + key + model，
/// 调任意 chat completions endpoint（OpenAI / DeepSeek / 硅基流动 / 本地 ollama 都行）。
///
/// 设计取舍：
/// - 真正发网络请求的 `chat` 是 actor 隔离的，避免并发竞态。
/// - 高层方法（generateSelfCompassion / generateNotificationBody / generateLetterToThem /
///   testConnection）是 @MainActor 的 free function，负责读 AppPreferences 和 fallback 决策。
/// - 不做 streaming、不做 retry、不做 token counting —— MVP 阶段用不上。
/// - timeout 用 URLSessionConfiguration.timeoutIntervalForRequest + Task group 双保险。
/// - base url 兼容：用户填 ".../v1" / ".../v1/" / "https://x.com" / "https://x.com/" 都行，
///   内部归一化为 "{origin}/v1/chat/completions"。
actor AIService {
    static let shared = AIService()

    enum AIServiceError: Error, LocalizedError {
        case disabled
        case notConfigured
        case invalidURL
        case http(status: Int, body: String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .disabled:        return "AI 未启用"
            case .notConfigured:   return "AI 未配置（缺 base-url 或 key）"
            case .invalidURL:      return "base-url 不合法"
            case .http(let s, _):  return "HTTP \(s)"
            case .decode:          return "响应解析失败"
            }
        }
    }

    /// 当前请求体快照：actor 内部不读 AppPreferences，调用方在 @MainActor 上
    /// 准备好这 4 个值再传进来。
    struct RequestSpec: Sendable {
        let baseURL: String
        let model: String
        let apiKey: String
    }

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Low-level chat

    /// 通用 chat completion。返回第一个 choice 的 content。
    /// 调方负责 prompt、temperature、max_tokens、timeout。
    func chat(
        spec: RequestSpec,
        system: String,
        userMessage: String,
        temperature: Double,
        maxTokens: Int,
        timeout: TimeInterval
    ) async throws -> String {
        let endpoint = try Self.normalizeEndpoint(spec.baseURL)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(spec.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": spec.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": userMessage],
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.session.data(for: req) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CancellationError()
            }
            // 第一个完成的（成功或失败）就赢，剩下的 cancel
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        guard let http = resp as? HTTPURLResponse else {
            throw AIServiceError.decode("response not HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.http(status: http.statusCode, body: body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.decode("missing choices[0].message.content")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Endpoint normalization

    /// "https://api.openai.com/v1" / ".../v1/" / "https://x.com" / "https://x.com/"
    ///  → "https://api.openai.com/v1/chat/completions"
    static func normalizeEndpoint(_ base: String) throws -> URL {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw AIServiceError.invalidURL
        }
        // 去掉尾部分隔符
        while s.hasSuffix("/") { s.removeLast() }
        // 已经有 /v1 结尾就不补
        if s.hasSuffix("/v1") {
            s += "/chat/completions"
        } else {
            s += "/v1/chat/completions"
        }
        guard let final = URL(string: s) else {
            throw AIServiceError.invalidURL
        }
        return final
    }
}

// MARK: - High-level content generators (MainActor, AppPreferences 在这里读)

/// 1 句自我关怀文案。失败 → 从 SelfCompassionPhrases 抽一条。
/// timeout 默认 2.0s，超时直接降级。
@MainActor
func generateSelfCompassion(for missing: Missing) async -> String {
    let prefs = AppPreferences.shared
    guard prefs.aiEnabled, prefs.aiIsConfigured, let key = prefs.aiAPIKey else {
        return SelfCompassionPhrases.phrases.randomElement() ?? ""
    }
    let spec = AIService.RequestSpec(
        baseURL: prefs.aiBaseURL,
        model: prefs.aiModel,
        apiKey: key
    )
    let ctx = AIServiceContext.description(for: missing)
    let system = """
    你是一个温柔、克制、懂亲密关系的朋友。用户刚记下一笔想念。
    请用 1 句话（不超过 30 字）回应，要求：
    1. 不评判、不说教、不鸡汤；
    2. 短而具体，不堆形容词；
    3. 允许安静、允许"什么都不做也行"；
    4. 不要 emoji，不要"亲爱的"，不要"你应该"。
    直接给出那 1 句话，不要任何前缀解释。
    """
    let user = "上下文：\(ctx)"
    do {
        let text = try await AIService.shared.chat(
            spec: spec,
            system: system,
            userMessage: user,
            temperature: prefs.aiTemperature,
            maxTokens: prefs.aiMaxTokens,
            timeout: prefs.aiRequestTimeout
        )
        return AIServiceContext.firstCleanLine(text)
    } catch {
        NSLog("[AIService] selfCompassion fallback: \(error.localizedDescription)")
        return SelfCompassionPhrases.phrases.randomElement() ?? ""
    }
}

/// 通知 body。失败 → fixed 模板。
/// timeout 给 1.5s（通知场景对延迟敏感），让用户感觉"立刻就有反馈"。
@MainActor
func generateAINotificationBody(for missing: Missing) async -> String {
    let prefs = AppPreferences.shared
    let fallback = AIServiceContext.fixedNotificationBody(for: missing)
    guard prefs.aiEnabled, prefs.aiIsConfigured, let key = prefs.aiAPIKey else {
        return fallback
    }
    let spec = AIService.RequestSpec(
        baseURL: prefs.aiBaseURL,
        model: prefs.aiModel,
        apiKey: key
    )
    let ctx = AIServiceContext.description(for: missing)
    let system = """
    你是一个情感 app 的文案编辑。用户刚记录了一笔想念。
    请生成 1 行通知正文（20-40 字），要求：
    1. 开头固定为 "想念 {对象}";
    2. 之后接 1 句温柔的注脚（不夸张、不命令、不提建议）;
    3. 不要 emoji 开头，不要"亲爱的"，不要"你应该"。
    """
    let user = "上下文：\(ctx)"
    do {
        let text = try await AIService.shared.chat(
            spec: spec,
            system: system,
            userMessage: user,
            temperature: prefs.aiTemperature,
            maxTokens: 120,
            timeout: 1.5
        )
        return AIServiceContext.firstCleanLine(text)
    } catch {
        NSLog("[AIService] notificationBody fallback: \(error.localizedDescription)")
        return fallback
    }
}

/// "致 TA 的话"。失败 → 3 封备选信里抽一封。
@MainActor
func generateLetterToThem(for missing: Missing) async -> String {
    let prefs = AppPreferences.shared
    let fallback = LetterTemplates.fallback.randomElement() ?? LetterTemplates.fallback[0]
    guard prefs.aiEnabled, prefs.aiIsConfigured, let key = prefs.aiAPIKey else {
        return fallback
    }
    let spec = AIService.RequestSpec(
        baseURL: prefs.aiBaseURL,
        model: prefs.aiModel,
        apiKey: key
    )
    let ctx = AIServiceContext.description(for: missing)
    let system = """
    你是一个温柔的朋友，替用户给 TA 写一段"想对 TA 说、但还没发出去"的话。
    要求：
    1. 80-140 字，1 段或 2 段都可以；
    2. 第一人称"我"，称呼 TA 为"你"或用户的对象名（不要用"亲爱的"）；
    3. 不戏剧化、不强迫对方回应、不承诺"我会怎样怎样"；
    4. 温柔、具体、克制 —— 重点是当下这一刻的感受，不是长篇大论；
    5. 不要 emoji，不要 markdown 加粗，不要"——题记"之类的装饰。
    只返回那段话本身，不要任何前缀。
    """
    let user = "上下文：\(ctx)"
    do {
        let text = try await AIService.shared.chat(
            spec: spec,
            system: system,
            userMessage: user,
            temperature: prefs.aiTemperature,
            maxTokens: 300,
            timeout: max(prefs.aiRequestTimeout, 3.0)
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        NSLog("[AIService] letter fallback: \(error.localizedDescription)")
        return fallback
    }
}

/// 健康检查，Settings 的"测试连接"按钮用。
@MainActor
func testAIConnection() async -> Result<String, Error> {
    let prefs = AppPreferences.shared
    guard prefs.aiEnabled, prefs.aiIsConfigured, let key = prefs.aiAPIKey else {
        return .failure(AIService.AIServiceError.notConfigured)
    }
    let spec = AIService.RequestSpec(
        baseURL: prefs.aiBaseURL,
        model: prefs.aiModel,
        apiKey: key
    )
    do {
        let text = try await AIService.shared.chat(
            spec: spec,
            system: "你是一个测试连接是否正常的助手，请只回 OK。",
            userMessage: "ping",
            temperature: 0.0,
            maxTokens: 10,
            timeout: 8
        )
        return .success(text)
    } catch {
        return .failure(error)
    }
}

// MARK: - Context + helpers (MainActor 范围内，能读 AppPreferences)

enum AIServiceContext {
    /// 把 Missing 拍平成一段人类可读描述，给 prompt 用。
    @MainActor
    static func description(for missing: Missing) -> String {
        let who = missing.who.isEmpty ? "TA" : missing.who
        let mood = missing.mood.label
        let intensity = missing.intensity.label
        let triggers = missing.triggerTags.map(\.label).joined(separator: "、")
        var parts: [String] = []
        parts.append("对象：\(who)")
        parts.append("心情：\(mood)")
        parts.append("程度：\(intensity)")
        if !triggers.isEmpty { parts.append("触发：\(triggers)") }
        parts.append("时间：\(timeOfDayDescription(for: missing.createdAt))")
        return parts.joined(separator: "，")
    }

    @MainActor
    static func timeOfDayDescription(for date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        switch h {
        case 5..<11:  return "清晨"
        case 11..<14: return "中午"
        case 14..<18: return "下午"
        case 18..<22: return "晚上"
        default:      return "深夜"
        }
    }

    @MainActor
    static func fixedNotificationBody(for missing: Missing) -> String {
        let base = "心情：\(missing.mood.label)　程度：\(missing.intensity.label)"
        let triggerPart: String
        if AppPreferences.shared.notificationIncludeTriggers,
           !missing.triggerTags.isEmpty {
            triggerPart = "　触发：" + missing.triggerTags.map(\.displayString).joined(separator: " ")
        } else {
            triggerPart = ""
        }
        return base + triggerPart
    }


    /// 清洗 AI 返回文案:
    /// 1) 剥 <think>...</think> / <reasoning>...</reasoning> / <reflection>...</reflection>
    ///    推理块 — DeepSeek R1 / QwQ / OpenAI o1 等 reasoning model 会把
    ///    chain-of-thought 当可见输出一起返回, system prompt 拦不住
    ///    (用户上一轮反馈的 "<think>" bug 就是这原因)。
    ///    模式允许未闭合 / 跨行 ([\\s\\S]*? + (?:close|$)), 避免 truncated
    ///    think 块把后面真正的回复也吞掉。
    /// 2) 剥 smart quotes / ASCII 引号 / 全角单引号。
    /// 3) 修剪首尾空白。
    /// 4) 取第一个非空 line。
    /// 返回 nil 表示清洗后为空 (调用方走 hardcoded fallback)。
    static func cleanAIPhrase(_ text: String) -> String? {
        var cleaned = text
        let patterns = [
            "<\\s*think\\s*>[\\s\\S]*?(?:<\\s*/\\s*think\\s*>|$)",
            "<\\s*reasoning\\s*>[\\s\\S]*?(?:<\\s*/\\s*reasoning\\s*>|$)",
            "<\\s*reflection\\s*>[\\s\\S]*?(?:<\\s*/\\s*reflection\\s*>|$)",
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }
        cleaned = cleaned
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "‘", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // 只按 newline 切 (旧 firstCleanLine 的语义), 保留首行里的空格 / 标点。
        // 不要按 whitespace 切 — "real response" 会被切成 ["real", "response"]
        // 只取第一个, 丢了一半内容。
        let lines = cleaned
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.first
    }

    /// 旧 firstCleanLine 名字保留, delegate 到 cleanAIPhrase 兼容老调用方。
    /// 永远不返回空 (空就回 cleaned 原文)。
    static func firstCleanLine(_ text: String) -> String {
        cleanAIPhrase(text) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Letter templates (fallback)

/// 3 封备选信。AIService 生成失败时随机抽一封。
/// 短、克制、不戏剧化、和产品"自我关怀"基调对齐。
enum LetterTemplates {
    static let fallback: [String] = [
        """
        我在想着你。
        没有什么具体的事，只是这一刻，
        我希望你知道。
        """,
        """
        你大概不知道我刚记下这一笔。
        我也没有要你现在回我什么，
        只是想说，我想你。
        """,
        """
        这个时间点想到你。
        没什么事，就是想告诉你，
        你在某个人的心里，被记了一下。
        """,
    ]
}
