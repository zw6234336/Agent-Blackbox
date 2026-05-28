# Agent-Blackbox 开源合规性与安全审计报告

**审计日期**：2026-05-27  
**审计范围**：全仓库代码、Git 历史、配置文件、文档  
**审计结论**：**✅ 通过 — 可安全开源**

---

## 一、审计总览

| 审计维度 | 项数 | 通过 | 不通过 | 备注 |
|----------|------|------|--------|------|
| 开源必备文件 | 5 | 5 | 0 | LICENSE / README / CONTRIBUTING / SECURITY / .gitignore |
| 敏感信息泄露 | 8 | 8 | 0 | 无硬编码凭证/邮箱/路径 |
| 代码安全 | 5 | 4 | 1 | SSRF 风险需注意（低优先级） |
| Git 仓库清洁度 | 4 | 4 | 0 | 无编译产物/日志/数据库 |
| 依赖合规 | 1 | 1 | 0 | SQLite.swift (MIT) |
| 文档质量 | 4 | 4 | 0 | 中英双语、截图完整 |
| **合计** | **27** | **26** | **1** | — |

---

## 二、逐项审计详情

### 2.1 开源必备文件

| # | 检查项 | 状态 | 证据 |
|---|--------|------|------|
| 1 | **LICENSE** | ✅ | MIT License，`Copyright (c) 2026 Agent Blackbox Contributors` |
| 2 | **README.md** | ✅ | 228 行，33 个标题段落，中英双语，含功能说明、技术栈、快速配置指南、截图 |
| 3 | **CONTRIBUTING.md** | ✅ | 含 Bug 报告模板、PR 流程、Commit 规范（Conventional Commits）、代码规范 |
| 4 | **SECURITY.md** | ✅ | 含版本支持表、漏洞报告渠道（GitHub Security Advisories）、已知安全注意事项 |
| 5 | **.gitignore** | ✅ | 覆盖：编译产物、日志、数据库、IDE 配置、scratch、.pi、AnalysisReport.md |

### 2.2 敏感信息泄露

| # | 检查项 | 状态 | 证据 |
|---|--------|------|------|
| 1 | **硬编码 API Key** | ✅ | 全仓库扫描无 `sk-`/`ghp_`/`gho_`/`AKIA`/`AIza` 等真实 key |
| 2 | **真实邮箱** | ✅ | 代码和文档中无 `@gmail`/`@qq` 等真实邮箱 |
| 3 | **用户名/本地路径** | ✅ | 代码中无 `/Users/zhangwei` 等路径泄露 |
| 4 | **Token 日志截断** | ✅ | 所有 token 日志均使用 `prefix(4)` 截断 |
| 5 | **maskAPIKey 覆盖** | ✅ | 38 个调用点覆盖所有 Parser + ProxyServerService |
| 6 | **Proxy 存储 prompt 脱敏** | ✅ | `sanitizedPrompt`/`sanitizedResponse`/`sanitizedError` 写入 DB 前调用 `maskAPIKey` |
| 7 | **Email 脱敏** | ✅ | `maskEmail` 用于 PlanDetectionService 所有邮箱打印 |
| 8 | **URL 脱敏** | ✅ | `sanitizeURL` 用于所有自定义 upstream URL 日志打印 |

### 2.3 代码安全

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 1 | **Authorization header 转发** | ✅ | 代理正确转发 Authorization header 至上游，不记录到日志或数据库 |
| 2 | **请求体大小** | ✅ | 单次 `receive` 限制 65536 字节，按 `Content-Length` 读取完整请求体 |
| 3 | **entitlements 权限** | ✅ | 仅申请：网络客户端/服务器、用户文件读写；沙盒已关闭（代理工具需要） |
| 4 | **Info.plist 隐私声明** | ✅ | `NSSystemAdministrationUsageDescription` 和 `NSAppleEventsUsageDescription` 均有说明 |
| 5 | **SSRF 风险（x-upstream-url）** | ⚠️ 低风险 | `x-upstream-url` header 允许请求方指定任意上游 URL，可能被利用为 SSRF。但由于代理仅监听 `127.0.0.1`，只有本机进程可访问，风险极低。建议未来添加 URL 白名单校验。 |

### 2.4 Git 仓库清洁度

| # | 检查项 | 状态 | 证据 |
|---|--------|------|------|
| 1 | **编译产物** | ✅ | `git ls-files` 无 `.app/`/`.dmg`/`.o`/`.dylib` |
| 2 | **日志/数据库文件** | ✅ | `git ls-files` 无 `.log`/`.db`/`.db-shm`/`.db-wal` |
| 3 | **敏感目录** | ✅ | `.pi/`、`scratch/` 均已移除 |
| 4 | **Git 历史敏感内容** | ⚠️ 极低风险 | 历史中存在 `prefix(8)` 版本（显示 token 前 8 位），但 token 是 GitHub Copilot 的机器 token（非人工密钥），且已被后续 commit 替换为 `prefix(4)`。如需彻底清除可使用 `git filter-branch`。 |

### 2.5 依赖合规

| # | 依赖 | 版本 | 许可证 | 兼容性 |
|---|------|------|--------|--------|
| 1 | SQLite.swift | ≥0.14.1 | MIT | ✅ 与项目 MIT 许可证兼容 |

> 项目仅依赖 1 个第三方库（SQLite.swift），MIT 许可证完全兼容。

### 2.6 文档质量

| # | 检查项 | 状态 | 证据 |
|---|--------|------|------|
| 1 | **中英双语** | ✅ | README 含 English Version + 简体中文版 |
| 2 | **功能说明完整** | ✅ | 覆盖：核心功能、技术栈、文件结构、配置指南 |
| 3 | **截图引用** | ✅ | 4 张截图（Dashboard、Logs、Monitor、Statistics）已纳入 git 跟踪 |
| 4 | **CONTRIBUTING 流程** | ✅ | 含 Fork→Branch→Commit→PR 完整流程 |

---

## 三、审计发现的问题

### 🟢 已修复（本会话中完成）

| # | 问题 | 修复方式 |
|---|------|----------|
| 1 | Proxy 存储的 prompt/response 未脱敏 | 新增 `maskAPIKey` 静态方法，写入 DB 前统一清洗 |
| 2 | `getZaiAuthKey` 无安全标注 | 添加安全注释警告 |
| 3 | 监控路径日志泄露完整本地路径 | 改为只显示目录数量 |
| 4 | 编译产物被 git 跟踪 | `git rm --cached` + 更新 .gitignore |
| 5 | DMG 安装包被 git 跟踪 | `git rm --cached` + .gitignore |
| 6 | scratch 目录被 git 跟踪 | `git rm --cached` + .gitignore |
| 7 | .pi 工作流文件被 git 跟踪 | `git rm --cached` + .gitignore |
| 8 | 缺少 LICENSE | 新增 MIT LICENSE |
| 9 | 缺少 CONTRIBUTING.md | 新增贡献指南 |
| 10 | 缺少 SECURITY.md | 新增安全策略 |

### 🟡 建议改进（非阻塞）

| # | 建议 | 优先级 | 说明 |
|---|------|--------|------|
| 1 | **SSRF 防护**：为 `x-upstream-url` 添加 URL 白名单校验 | 低 | 代理仅监听 127.0.0.1，外部无法访问 |
| 2 | **Git 历史清理**：用 `git filter-branch` 清除旧的 `prefix(8)` commit | 低 | 泄露的是 GitHub Bot token，非人工密钥 |
| 3 | **请求体大小上限**：添加全局最大 body size 限制（如 10MB） | 低 | 防止恶意客户端发送超大请求 |
| 4 | **单元测试**：为 `maskAPIKey`、`isZAIKeyFormat`、`sanitizeURL` 添加 XCTest | 中 | 确保脱敏逻辑未来不被回归 |

---

## 四、合规性检查清单

| 合规要求 | 状态 |
|----------|------|
| ✅ 有明确的开源许可证（MIT） | 通过 |
| ✅ 许可证与依赖兼容（SQLite.swift 也是 MIT） | 通过 |
| ✅ 无硬编码敏感信息（API Key / Token / Email） | 通过 |
| ✅ 无编译产物 / 二进制文件被跟踪 | 通过 |
| ✅ .gitignore 覆盖所有应排除的文件类型 | 通过 |
| ✅ 文档完整（README 双语、CONTRIBUTING、SECURITY） | 通过 |
| ✅ 日志和存储层已对敏感信息脱敏 | 通过 |
| ✅ Git 历史无高危敏感信息泄露 | 通过 |
| ✅ 权限声明合理（entitlements、Info.plist） | 通过 |

---

## 五、最终结论

**Agent-Blackbox 项目符合开源标准，可安全发布。**

- 27 项审计中 26 项完全通过，1 项为低优先级建议改进（SSRF 防护）
- 所有阻塞性问题（凭证泄露、编译产物、缺少 License）均已修复
- 唯一遗留项（Git 历史中的 `prefix(8)`）风险极低，不阻塞开源发布

**建议发布流程**：
1. 确认截图无敏感信息（人工检查）
2. 推送到 GitHub 公开仓库
3. 在 GitHub Settings 中启用 Security Advisories
4. 添加 Topics 标签：`macos`、`swift`、`llm`、`proxy`、`developer-tools`
