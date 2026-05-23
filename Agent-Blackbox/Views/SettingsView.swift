import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var database: DatabaseService

    var body: some View {
        Form {
            Section("监控设置") {
                Toggle("开机自动启动", isOn: $configService.config.autoStart)
                Toggle("启用通知", isOn: $configService.config.enableNotifications)
                Toggle("递归监控子目录", isOn: $configService.config.isRecursive)
            }

            Section("监控目录") {
                ForEach(configService.config.monitoredDirectories, id: \.self) { dir in
                    Text(dir)
                }
                Button("添加目录") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        let path = url.path
                        if !configService.config.monitoredDirectories.contains(path) {
                            configService.config.monitoredDirectories.append(path)
                        }
                    }
                }
            }

            Section("文件类型") {
                ForEach(configService.config.filePatterns, id: \.self) { pattern in
                    Text(pattern)
                }
            }

            Section("数据库") {
                Text("路径: \(configService.config.databasePath)")
                Button("清空数据库") {
                    Task {
                        await database.clearAllLogs()
                    }
                }
                    .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 400)
        .onChange(of: configService.config) { _ in
            configService.save()
        }
    }
}
