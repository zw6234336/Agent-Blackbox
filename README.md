# Agent-Blackbox

一个原生 macOS 应用，用于监控、收集和管理大模型（LLM）在 Mac 上的所有运行日志。

## 功能特性

- 🔍 实时监控文件系统中的 LLM 日志
- 📊 解析和展示日志内容（Prompt、Response、Tokens）
- 💾 本地数据库存储日志数据
- 🔎 强大的搜索和过滤功能
- 📤 导出日志为 CSV/JSON 格式
- 🎨 原生 macOS SwiftUI 界面
- 🔔 新日志通知提醒

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 14.0 或更高版本（用于从源码构建）

## 技术栈

- Swift
- SwiftUI
- Combine
- FSEvents（文件系统监控）
- SQLite（数据存储）

## 安装

### 从源码构建

1. 克隆仓库：
```bash
git clone https://github.com/zw6234336/Agent-Blackbox.git
cd Agent-Blackbox
```

2. 使用 Xcode 打开项目（推荐）：
```bash
open Package.swift
```

3. 选择 **AgentBlackbox** scheme，选择 **My Mac** 目标，点击运行

## 使用说明

### 首次设置

1. 启动应用后，授予必要的文件访问权限
2. 在设置中配置要监控的目录
3. 点击「开始监控」按钮

### 监控的默认路径

应用会自动监控以下常见的日志目录：
- `~/Library/Logs/`
- `~/Library/Application Support/`
- `~/.cache/`
- `~/.config/`

### 支持的 LLM 平台

| 平台 | 说明 |
|------|------|
| **Claude** (Anthropic) | Claude Desktop 应用日志 |
| **GitHub Copilot** | VS Code / JetBrains 插件日志 |
| **ChatGPT** (OpenAI) | ChatGPT Desktop 应用日志 |
| **DeepSeek** | DeepSeek 客户端日志 |
| **ChatGLM** (智谱 AI) | ChatGLM 本地及 API 日志 |
| **Pi** (Inflection AI) | Pi 客户端日志 |
| **Ollama** | 本地 Ollama 服务日志（`~/.ollama/logs/`） |
| **Gemini** (Google) | Gemini 应用日志 |
| **Qwen** (通义千问) | 通义千问客户端日志 |
| **Mistral** | Mistral 客户端日志 |
| **Custom** | 自定义目录和日志格式 |

## 数据隐私

- 所有日志数据仅存储在本地
- API 密钥自动脱敏处理
- 不会上传任何数据到云端

## 开发

### 项目结构

```
Agent-Blackbox/
├── App/              # 应用入口
├── Views/            # SwiftUI 视图
├── Models/           # 数据模型
├── Services/         # 核心服务
├── Utils/            # 工具类
└── Resources/        # 资源文件
```

### 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 作者

[@zw6234336](https://github.com/zw6234336)
