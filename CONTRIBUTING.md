# Contributing to Agent Blackbox

感谢你对 Agent Blackbox 的关注！我们欢迎任何形式的贡献。

## 如何贡献

### 报告 Bug

1. 在 [Issues](../../issues) 中搜索是否已有相关问题
2. 如果没有，创建新 Issue 并包含：
   - macOS 版本
   - Agent Blackbox 版本
   - 复现步骤
   - 预期行为 vs 实际行为
   - 如有可能，附上截图

### 提交代码

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/my-feature`
3. 提交改动：`git commit -m 'feat: 添加新功能'`
4. 推送分支：`git push origin feature/my-feature`
5. 创建 Pull Request

### Commit 规范

请使用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
feat: 新功能
fix: 修复 bug
docs: 文档更新
refactor: 重构（不改变功能）
perf: 性能优化
test: 测试
chore: 构建/工具链变更
```

### 代码规范

- Swift 5.10+ / SwiftUI
- 使用 `async/await` 进行异步操作
- 所有公开 API 需包含文档注释
- 遵循 Swift API Design Guidelines

## 安全问题

如果你发现了安全漏洞，请**不要**在公开 Issue 中报告。请发送邮件至项目维护者。

## 许可证

提交代码即表示你同意你的贡献将在 MIT 许可证下发布。
