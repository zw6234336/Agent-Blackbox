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

2. 使用 Xcode 打开项目：
```bash
open Agent-Blackbox.xcodeproj
```

3. 在 Xcode 中选择目标设备并点击运行按钮

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

- OpenAI (GPT-3.5, GPT-4)
- Anthropic (Claude)
- 本地运行的模型
- 自定义日志格式

## 主要视图截图（安装后核心界面）

> 以下为当前应用的核心界面示意截图，帮助你快速了解安装后最常使用的页面、可查看的数据以及可调整项。

### 1) 监控视图（Monitor）

![监控视图](docs/screenshots/main-view-monitor.png)

你可以看到：
- 当前监控状态（是否正在监控）
- 最近检测到的日志文件列表
- 当前生效的监控目录

你可以调整：
- 开始/停止监控
- 监控目录与文件匹配规则（在设置中修改后生效）

### 2) 日志视图（Log List + Detail）

![日志视图](docs/screenshots/main-view-logs.png)

你可以看到：
- 左侧日志列表（模型名、时间）
- 搜索过滤结果
- 右侧日志详情（模型、时间、来源文件、Token）
- Prompt / Response / 错误信息

你可以调整：
- 通过搜索框筛选日志
- 在不同日志条目间切换查看完整交互内容

### 3) 统计视图（Statistics）

![统计视图](docs/screenshots/main-view-statistics.png)

你可以看到：
- 总调用次数、错误次数、Token 用量、活跃模型数
- 调用趋势（正常/错误）
- 错误趋势变化

你可以调整：
- 时间范围（1H / 6H / 24H / 7D / 30D）

## 数据隐私

- 所有日志数据仅存储在本地
- API 密钥自动脱敏处理
- 不会上传任何数据到云端

## 开发

### 项目结构

```
Agent-Blackbox/
├── Agent-Blackbox/
│   ├── AgentBlackboxApp.swift
│   ├── ContentView.swift
│   ├── Views/
│   ├── Models/
│   ├── Services/
│   ├── Utils/
│   ├── Resources/
│   └── Info.plist
├── Package.swift
└── Agent-Blackbox.entitlements
```

### 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 作者

[@zw6234336](https://github.com/zw6234336)
