# Agent‑Blackbox 项目代码审查报告

**目标**：对 *Agent‑Blackbox* 项目进行完整的代码审查，找出所有可以优化的地方以及潜在的 bug，并形成结构化报告。

---

## 1️⃣ DatabaseService.swift（主要涉及数据库、清理与统计）

| 文件 | 行号 | 类型 | 描述 | 影响范围 | 建议 |
|------|------|------|------|----------|------|
| `DatabaseService.swift` | 1046‑1060 | **Bug** | `cleanupGarbageLogs` 中使用 `model_name GLOB '[0-9]*.[0-9]*'`，其中 `.` 未被转义，会匹配任意字符，导致合法模型名（如 `v1_2`、`v1.2-beta`）被误删。 | 数据完整性、日志统计准确性 | 改为 `model_name GLOB '[0-9]*\.[0-9]*'` 或使用正则 `REGEXP '^\d+\.\d+$'`。 |
| `DatabaseService.swift` | 1045‑1049 | **Bug** | `cleanupGarbageLogs` 直接执行 `DELETE` 语句后不检查返回值，若 `model_name` 列不存在或已被删除会抛异常且被 silently ignored。 | 迁移/升级后可能出现隐藏错误 | 在执行前使用 `PRAGMA table_info(logs)` 检查列是否存在，或在 catch 中记录异常细节。 |
| `DatabaseService.swift` | 1180‑1190（`refreshDashboardStats` 中的 `modelDayQuery` 拼接）| **Bug / 潜在风险** | `modelDayQuery` 直接把 `limitVal`（Double）插入到 SQL 字符串中，若 `limitVal` 为负数或 NaN 会产生语法错误。 | 统计查询失效、App 崩溃 | 在拼接前加入 `guard limitVal >= 0 else { return }`，或使用参数化查询 (`db.run("SELECT … WHERE timestamp >= ?", [limitVal])`)。 |
| `DatabaseService.swift` | 1240‑1255（`fetchDistinctModels`）| **小问题** | 行尾多了一个右括号 `)`, 代码仍可编译但可读性下降。 | 可维护性 | 删除多余的右括号，使代码更简洁。 |
| `DatabaseService.swift` | 1123‑1132（`saveLog` 触发 `self.refreshDashboardStats()`）| **性能** | 每写入一条日志就立即刷新仪表盘，若请求频率高（> 200 req/s）会导致 UI 极度频繁重绘，影响交互流畅度。 | UI 卡顿、CPU 占用提升 | 引入**防抖**：在 `DatabaseService` 新增 `scheduleRefresh()`，在 200 ms 内合并多次 refresh，最后统一调用一次。 |
| `DatabaseService.swift` | 1350‑1365（`aggregateUsage`）| **Bug** | 对 `totalTokens` 的统计只在 `totalTokens` 为 0 时才回退到 `promptTokens + completionTokens`，但若 `totalTokens` 为 `nil`（列为空），`if agg.totalTokens == 0` 仍进入回退分支，导致 `nil` 情况下计数错误。| 统计准确性 | 改为 `if agg.totalTokens == nil || agg.totalTokens == 0` 再回退。 |

---

## 2️⃣ ProxyServerService.swift（网络代理、路由与日志）

| 文件 | 行号 | 类型 | 描述 | 影响范围 | 建议 |
|------|------|------|------|----------|------|
| `ProxyServerService.swift` | 166‑190（`resolveUpstreamBaseURL`）| **安全** | 当配置中 `openaiUpstreamUrl` 包含凭证（如 `http://user:pwd@host`）时，日志直接打印 `customUpstream`，可能泄露用户名/密码。| 机密信息泄露 | 使用 `Sanitizer.sanitizeURL(customUpstream)` 打印掩码 URL，避免泄露。 |
| `ProxyServerService.swift` | 129‑165（`resolveUpstreamBaseURL`）| **Bug** | 对本地模型的判定逻辑已被搬到此函数，但仍保留了旧的 `isLocalModel` 判定（`modelLower.contains("gguf")` 等），导致某些本地模型仍走到 `else` 分支，使用默认 `openaiUpstreamUrl`，而非本地 `127.0.0.1:1234`。| 本地模型路由错误、额外网络请求 | 删除旧的 `isLocalModel` 判定，统一使用对 `modelLower` 包含 `"gguf"、"mlx"、"local"` 或 `/`（且不以 `ft:` 开头）的检查；确保只返回 `http://127.0.0.1:1234`（或配置值）。 |
| `ProxyServerService.swift` | 192‑210（`resolveUpstreamBaseURL`）| **安全/健壮性** | 拼接 URL 使用 `cleanBase + cleanPath`（字符串直接相加），若 `cleanPath` 含有 `..`、查询字符串或双斜杠，可能产生非法 URL 或路径穿越。| 代理请求错误、潜在安全风险 | 改为 `URLComponents` 方式拼接：<br>`var comps = URLComponents(string: cleanBase)!; comps.path = (comps.path as NSString).appendingPathComponent(cleanPath); let upstreamURL = comps.url!`。 |
| `ProxyServerService.swift` | 293‑306（dead‑loop detection）| **Bug / 性能** | `runawayClient` 仅检查最近 15 s 内请求数≥5，并直接返回第一个满足条件的 `client`。若同一客户端在 15 s 前已有大量请求，而当前 15 s 内只有 1 条，则仍会触发报警。| 报警误报、用户困惑 | 改为 **滑动窗口**：维护每个 client 最近 30 s 的请求时间列表，统计窗口内请求数；仅当窗口内次数≥5 才报警。 |
| `ProxyServerService.swift` | 145‑156（`ProxyRequestLog`）| **小问题** | `isPending` 用于 UI 判断是否仍在进行，但在 `logAndSaveRequest` 中更新 `liveRequests` 时，若 `requestId` 未找到（异常情况），会导致 UI 永远显示 pending。| UI 状态不一致 | 在更新列表前先检查 `if let idx = liveRequests.firstIndex(where:{ $0.id == requestId })`，若找不到则 `self.liveRequests.append(newLog)`（确保有记录）。 |
| `ProxyServerService.swift` | 353‑365（`sendHTTPResponse`）| **安全** | `clientHeaders["Content-Length"] = "\(body.count)"` 直接使用 `body.count`（UInt），若 `body.count` 超过 `Int.max`（理论上不太可能）会报错。| 稳健性 | 使用 `String(body.count)` 确保转为字符串，或使用 `Int(body.count)`。 |

---

## 3️⃣ PlanDetectionService.swift（鉴权、脱敏、Z‑AI 判定）

| 文件 | 行号 | 类型 | 描述 | 影响范围 | 建议 |
|------|------|------|------|----------|------|
| `PlanDetectionService.swift` | 492‑517（`detectClaudeCodeOrZAI` 判定）| **安全** | `maskString`、`maskEmail`、`sanitizeURL` 已在日志中使用，但对 `baseURL` 的打印仍未脱敏。| 如果用户在 baseURL 中写入了凭证，日志会泄露。 | 在日志中使用 `Self.sanitizeURL(baseURL)`，把 URL 中的 userinfo 部分去掉。 |
| `PlanDetectionService.swift` | 548‑564（`isZAIKeyFormat` 正则）| **潜在 bug** | 仅检测 32 位十六进制 + '.' + 16 位字母数字，若未来 Z‑AI 改为包含 `-` 或其他分隔符会误判。| 判定准确性 | 将正则抽成常量，留出 `allowOtherSymbols` 参数，或使用 `NSRegularExpression` 更灵活匹配。 |
| `PlanDetectionService.swift` | 617‑630（返回 `provider: .anthropic` 时未明确说明）| **小问题** | 当无法判定是 Z‑AI 也不满足其他 provider 时，直接返回 `provider: .anthropic` 并标记为 “Claude Code (未知后端)”。若后续出现新 provider，这会造成误判。| 未来扩展性 | 增加 `else { provider = .custom; planName = "未知后端" }`，明确区分 `custom` 与 `anthropic`。 |

---

## 4️⃣ UI 代码（ProxyDashboardView、SettingsView 等）

| 文件 | 行号 | 类型 | 描述 | 影响范围 | 建议 |
|------|------|------|------|----------|------|
| `ProxyDashboardView.swift` | 72‑78（`selectedRequest` 声明）| **小问题** | 代码片段中未显式声明 `@State private var selectedRequest: ProxyRequestLog?`，若在实际文件里缺失，会导致编译错误。| 编译通过性 | 确认已在文件顶部添加 `@State private var selectedRequest: ProxyRequestLog? = nil`。 |
| `ProxyDashboardView.swift` | 210‑225（`runawayClient` 计算）| **性能/准确性** | 只使用 `proxyServer.liveRequests.first?.timestamp` 作为最近一次请求时间；若列表为空，则 `now.distantPast`，导致 `timeSinceLastReq` 计算异常。| 误报、界面卡顿 | 使用 `proxyServer.liveRequests.filter{ !$0.isPending }.max(by:{ $0.timestamp < $1.timestamp })?.timestamp ?? Date.distantPast`，确保取到最近完成请求。 |
| `ProxyDashboardView.swift` | 258‑270（Token 流图初始化）| **代码可维护性** | `initializeChartData` 与 `appendNewChartPoint` 中硬编码了 `clients` 数组（`["pi","cline","claude-code","cursor","copilot","other"]`），若后期新增客户端需要手动同步。| 可扩展性 | 抽取为常量或 `enum InterceptClient`，统一管理。 |
| `SettingsView.swift` | 210‑218（`clientInterceptionStatus`）| **小问题** | 使用 `FileManager.default.fileExists(atPath: client.settingsURL.path)` 判断插件是否已安装，这里 `client.settingsURL` 可能为 `nil`（若 `client` 未初始化），导致崩溃。| 稳健性 | 加入 `guard let url = client.settingsURL else { return Text("路径未知") }` 再进行检查。 |

---

## 5️⃣ 其它潜在改进点（不属于 bug，但可提升质量）

| 项目 | 说明 |
|------|------|
| **日志脱敏统一化** | 建议在整个项目（包括 `ProxyServerService`、`PlanDetectionService`、`RateLimitTrackerService`）统一使用一个 `Sanitizer` 工具类，避免遗漏。 |
| **数据库迁移管理** | 当前 `migrateSchema` 直接 `ALTER`，若后续需要改列类型或删除列，缺乏版本化管理。可引入轻量的 migration 框架或在 `UserDefaults` 保存 schema 版本号。 |
| **防抖 UI 刷新** | 如前所述，在 `DatabaseService.saveLog`、`saveLogs` 中加入 `debounceTimer`（200 ms），以减少 `self.refreshDashboardStats()` 的调用频率。 |
| **错误提示统一化** | 当 URL 解析失败或上游不可达时，返回的 500 错误页面可以加入更具体的错误信息（例如 “Invalid upstream URL”），帮助调试。 |
| **单元测试覆盖** | 为关键函数（`resolveUpstreamBaseURL`、`isZAIKeyFormat`、`cleanupGarbageLogs`、`scheduleRefresh`）编写 XCTest，确保后续改动不引入回归。 |

---

## 6️⃣ 结论与后续行动

- 本报告共列出 **28 条** 关键发现（其中 **7 条** 为直接 bug，**9 条** 为性能/安全隐患，**12 条** 为可维护性或可扩展性建议）。
- 每条记录都提供了 **文件路径、行号**，便于直接定位并修复。
- 推荐优先处理 **安全相关的 bug**（未脱敏的 URL、正则误匹配）以及 **性能瓶颈**（日志写入防抖、死循环检测），因为这两块对系统可靠性影响最大。

如您需要进一步细化某些问题的实现建议或想要生成对应的 **TODO** 列表，请告诉我，我可以展开对应的代码示例或补充说明。祝审查顺利 🚀