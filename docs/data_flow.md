# Agent-Blackbox 数据流向图 (Data Flow)

本项目 `Agent-Blackbox` 是一个轻量级、原生的 macOS 状态监控与 LLM 请求统计工具。它采用**“双驱采集”**机制：
1. **动态采集通道**：通过本地代理网关拦截出网的 HTTP/HTTPS 请求进行分析。
2. **静态扫描通道**：通过 macOS FSEvents 机制监听编辑器和终端日志文件的变更并增量解析。

---

## 核心数据流向图

```mermaid
flowchart TD
    %% 定义颜色与圆角样式
    classDef client fill:#dcf8c6,stroke:#9fc98c,stroke-width:1.5px;
    classDef gateway fill:#d1ecf1,stroke:#bee5eb,stroke-width:1.5px;
    classDef scanner fill:#fff3cd,stroke:#ffeeba,stroke-width:1.5px;
    classDef database fill:#f8d7da,stroke:#f5c6cb,stroke-width:1.5px;
    
    %% 第一层：数据源
    subgraph T1 ["【第一层】数据源与客户端 (Sources & Clients)"]
        C_IDE["AI 客户端应用 <br/> (Cline / Claude Code / Cursor / Pi / Python SDK)"]
        F_SYS["本地文件系统 <br/> (App Support 日志 / vscdb 数据库)"]
    end
    
    %% 第二层：拦截器
    subgraph T2 ["【第二层】网关拦截与监控 (Capture & Listeners)"]
        GW_SVR["ProxyServerService <br/> (NWListener 端口 9999)"]
        FS_MON["FileMonitorService <br/> (FSEvents 文件变更监听)"]
    end
    
    %% 第三层：解析与路由
    subgraph T3 ["【第三层】动态分发与解析引擎 (Routing & Parsers)"]
        direction TB
        subgraph DynamicEngine ["动态网关解析"]
            ROUTE["resolveUpstreamBaseURL <br/> (智能识别模型及厂商)"]
            UP_COMP{"大模型厂商 API <br/> (OpenAI / Anthropic / Gemini / DeepSeek / Zhipu)"}
            TEE["ProxySessionDelegate <br/> (Tee 旁路流分流机制)"]
        end
        
        subgraph StaticEngine ["静态日志解析"]
            LOG_PAR["LogParserService <br/> (分配解析路由)"]
            TEMP_DB["/tmp 隔离副本只读连接 <br/> (安全只读模式，防 Cursor 锁死)"]
            PARSERS["解析器链 <br/> (Warp / Cline / Copilot / ClaudeDesktop)"]
        end
    end
    
    %% 第四层：存储与 UI 展示
    subgraph T4 ["【第四层】数据持久化与展示 (Storage & UI)"]
        DB["DatabaseService <br/> (SQLite.swift WAL 模式)"]
        UI["SwiftUI Dashboard <br/> (性能看板 / 历史日志 / 菜单控制栏)"]
    end

    %% -------------------- 数据流动连接 --------------------
    
    %% 动态采集路径 (Active Interception)
    C_IDE -->|1. 发送 API 请求| GW_SVR
    GW_SVR -->|2. 解析模型/请求体| ROUTE
    ROUTE -->|3. 智能转发请求| UP_COMP
    UP_COMP -->|4. 流式回传 Chunk| TEE
    TEE -->|5a. 响应流低延迟回传| C_IDE
    TEE -->|"5b. 旁路分流统计 (Token/时长/资费)"| DB
    
    %% 静态扫描路径 (Passive Monitoring)
    C_IDE -->|A. 追加运行历史/日志| F_SYS
    F_SYS -.->|B. 触发 FSEvents 变更通知| FS_MON
    FS_MON -->|C. 调度文件分析| LOG_PAR
    LOG_PAR -->|D1. 遇到 SQLite 数据库| TEMP_DB
    TEMP_DB -->|D2. 只读连接解析| PARSERS
    LOG_PAR -->|E. 遇到文本 log/jsonl| PARSERS
    PARSERS -->|F. 提取结构化 ParsedLog| DB
    
    %% 数据呈现
    DB -->|G. 响应式驱动更新| UI
    
    %% 应用样式映射
    class C_IDE,F_SYS client;
    class GW_SVR,ROUTE,UP_COMP,TEE gateway;
    class FS_MON,LOG_PAR,TEMP_DB,PARSERS scanner;
    class DB,UI database;
```

---

## 数据流详解

### 1. 动态采集通道 (Active Interception)

* **步骤 1：客户端接入**  
  在客户端应用（如 Cline 或 Python 脚本）中，将 Base URL 重定向至本地网关端口 `http://127.0.0.1:9999/v1`。
* **步骤 2 & 3：智能解析与路由**  
  [ProxyServerService](file:///Users/zhangwei/work/github/Agent-Blackbox/Agent-Blackbox/Services/ProxyServerService.swift) 利用底层套接字拦截流量。通过 `resolveUpstreamBaseURL` 方法，根据 Authorization Token 格式（如 OpenRouter）、自定义头部（如 `x-upstream-url`）或请求体模型名称（如 `glm-5.1` / `gemini`）自动完成转发域名的路由重写，将请求安全分发到对应的厂商接口。
* **步骤 4 & 5a：高并发流回传**  
  由于大模型接口广泛采用 SSE 流式输出，网关的 `ProxySessionDelegate` 采用 **Tee (旁路分流) 机制**。在流式传输期间，主数据流以 Chunk 为单位原封不动实时回传给客户端，确保毫秒级的交互延迟不受影响。
* **步骤 5b：旁路吞吐统计**  
  流式生成结束后，旁路通道会统计整个会话消耗的 Prompt Tokens、Completion Tokens 以及 API 响应时长与资费，整理为日志项存入数据库。

### 2. 静态扫描通道 (Passive Monitoring)

* **步骤 A & B：日志事件监听**  
  对于不支持修改 API 地址或自带日志记录的 IDE 工具（如 VS Code Copilot, Warp, Cursor），[FileMonitorService](file:///Users/zhangwei/work/github/Agent-Blackbox/Agent-Blackbox/Services/FileMonitorService.swift) 注册 macOS 的 FSEvents 机制，监听其在 `Application Support` 等系统目录下生成的日志与数据库变更。
* **步骤 C, D1 & D2：防锁死隔离解析**  
  针对 Cursor 产生的数据，其会将聊天记录写入 `state.vscdb` (SQLite)。为了防止与主编辑器争抢文件锁导致 Cursor 卡死崩溃，网关会将数据库拷贝至 `/tmp` 目录建立临时副本，再通过 [LogParserService](file:///Users/zhangwei/work/github/Agent-Blackbox/Agent-Blackbox/Services/LogParserService.swift) 的只读连接进行抓取解析。
* **步骤 E & F：日志增量抽取**  
  针对 `*.log` 或 `*.jsonl` 等流式日志文件，解析器链使用文件指针对尾部增量追加内容进行捕获，将提取的 `ParsedLog` 发送给数据库层。

### 3. 数据落库与 UI 联动 (Persistence & Presentation)

* **步骤 G：WAL SQLite 库与响应式渲染**  
  动态和静态捕获的所有数据最终交由 [DatabaseService](file:///Users/zhangwei/work/github/Agent-Blackbox/Agent-Blackbox/Services/DatabaseService.swift) 进行落库持久化。
* 数据库在初始化时已配置为 **WAL (Write-Ahead Logging) 模式**，保证高并发日志写入与前端 Dashboard 的高频查询两不冲突。落库完成后，网关界面的“实时连接流水”与“今日资费进度计”会自动通过 SwiftUI 响应式绑定进行渲染，呈现流畅的动态流动。
