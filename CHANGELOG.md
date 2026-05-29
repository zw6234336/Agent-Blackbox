# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- ResponsiveScrollView with activation observers to restore scroll after idle/App Nap
- `wakeUpScrollViews(in:)` recursive helper in AppDelegate for tab-switch scroll fix
- FileMonitorService debounce (2s coalescing) to prevent rapid re-parsing of `.vscdb` files
- Zoomable time range and scrollable navigation to token usage chart in DashboardView
- NativeScrollView (NSScrollView wrapper) replacing SwiftUI ScrollView for reliable scroll

### Changed
- Replaced remaining SwiftUI vertical `ScrollView` with `NativeScrollView` in DailySummaryView

---

## [0.9.0] - 2026-05-27

### Added
- `CONTRIBUTING.md` and `SECURITY.md` for open-source readiness
- Comprehensive bilingual README (English + 简体中文)
- Mermaid data flow diagram in `docs/data_flow.md`
- Application icon and refreshed documentation screenshots

### Security
- `maskAPIKey()` / `sanitizeURL` applied across all data paths
- Token logging restricted to first 4 characters
- Removed `app.log` from git history

### Changed
- Optimized ProxyDashboardView chart loop performance
- Refined gitignore rules for build artifacts and internal files

---

## [0.8.0] - 2026-05-26

### Fixed
- Database operations offloaded to background serial queue to prevent UI blocking
- Sanitized sensitive info in logs (API keys, emails)

---

## [0.7.0] - 2026-05-25

### Added
- Claude Code detection support (`.claude/` JSONL logs)
- Expanded RateLimit model fields (hourly, daily, monthly windows)
- Multi-model token trend chart with categorized color mapping
- Dismiss button for LogDetailView modal
- Collection and Compilation management sheets
- Rate limit editing UI
- FocusState for new compilation/collection sheet fields

### Changed
- Concurrency fixes in DatabaseService (`@MainActor`, serial queue)
- Removed cost estimation logic and cost-based rate limits
- Replaced AppKitTextField with SwiftUI TextField + FocusState

### Fixed
- Window activation and key focus management for macOS

---

## [0.6.0] - 2026-05-24

### Added
- **Local Proxy Gateway** (`ProxyServerService`) — NWListener on port 9999
  - Auto-detects target provider from token format or model name
  - Routes to 10+ cloud providers (OpenAI, Anthropic, Gemini, DeepSeek, Qwen, Zhipu, Kimi, OpenRouter, local)
  - SSE streaming support with tee (旁路) mechanism for low-latency passthrough
  - Token counting with estimation fallback
- **Client Auto-Interception** (`ClientInterceptionService`)
  - One-click proxy config for VS Code Cline, Cursor Cline, Claude Code CLI, Pi Agent
  - Automatic config restore on app exit
- **ProxyDashboardView** — real-time gateway monitoring with live ticker, session chart, heartbeat waveform
- **Compilation feature** — combine logs into shareable documents
- **Collection feature** — bookmark and organize logs
- **DailySummaryService** — LLM-powered daily report (DeepSeek / OpenAI / Anthropic)
- **DesktopWidgetService** — always-on-top mini floating window
- **GitIntegrationService** — track LLM usage per git commit
- Menu bar control for gateway/monitoring start/stop

### Fixed
- Pi parser log filtering and cleanup of misclassified logs
- FileMonitor event dispatch on main queue
- CompilationService optional binding safety

### Changed
- New compilation sheet refactored to standalone view
- LogListView selection state management improved

---

## [0.5.0] - 2026-05-23

### Added
- **14 log parsers**: ClaudeCodeCLI, ClaudeDesktop, Cline, CursorLog, CursorVSCDB,
  VSCodeCopilot, CopilotChatSession (JSON + JSONL), Pi, Warp, Amp, Antigravity,
  Ollama, GenericLLM
- **FSEvents-based FileMonitorService** with initial directory scan
- **DatabaseService** — SQLite via SQLite.swift with WAL mode, batch insert, full CRUD
- **DashboardView** — metrics grid, provider/model distribution, token trends
- **LogListView** — searchable/filterable log list with detail inspector
- **RateLimitTrackerService** — multi-dimensional RPM/TPM/daily/monthly monitoring
- **PlanDetectionService** — auto-detect Copilot/Cursor/Claude/Z.AI subscription tiers
- **SharePosterView** — visual usage summary PNG generator
- **StatisticsView** — trend charts with time-range picker
- **LogLocationView** — log source file browser
- **SettingsView** — full configuration panel
- Insurance planning demo views
- `LogParserProtocol` with `maskAPIKey`, `detectProvider`, date parsing helpers
- Extensions: wildcard matching, UUID deterministic hashing, formatting helpers
- `AppIcon.icns` and project assets

### Changed
- Extracted magic numbers/strings into constants
- Optimized stats and search update paths
- Tightened insurance navigation bindings

### Fixed
- Consistent timestamp boundary in trend queries
- Settings directory add and database clear actions
- Statistics counters using full database counts
