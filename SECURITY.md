# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

如果你发现了安全漏洞，请**不要**在 GitHub Issues 中公开报告。

请通过以下方式私下报告：

- 在 GitHub 上使用 [Security Advisories](../../security/advisories/new) 功能
- 或联系项目维护者

我们会在 48 小时内回复，并在确认后尽快发布修复。

### 已知安全注意事项

- Agent Blackbox 作为本地代理运行，监听 `127.0.0.1:9999`
- 代理会拦截并转发 HTTP 请求（包含 Authorization header）
- 所有日志在存储前已进行 API Key 脱敏处理
- 用户的 API Key 仅存储在本地 SQLite 数据库中，不会上传至任何服务器
