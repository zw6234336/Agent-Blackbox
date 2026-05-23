import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configService: ConfigService

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
                Button("添加目录") {}
            }

            Section("文件类型") {
                ForEach(configService.config.filePatterns, id: \.self) { pattern in
                    Text(pattern)
                }
            }

            Section("数据库") {
                Text("路径: \(configService.config.databasePath)")
                Button("清空数据库") {}
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
