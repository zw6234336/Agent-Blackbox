import SwiftUI

struct LogDetailView: View {
    let log: ParsedLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "模型", value: log.modelName ?? "N/A")
                        InfoRow(label: "时间", value: log.timestamp.formatted())
                        InfoRow(label: "文件", value: log.sourceFile)
                        if let tokens = log.tokensUsed {
                            InfoRow(label: "Tokens", value: "\(tokens)")
                        }
                    }
                }

                if let prompt = log.prompt {
                    GroupBox("Prompt") {
                        Text(prompt)
                            .textSelection(.enabled)
                    }
                }

                if let response = log.response {
                    GroupBox("Response") {
                        Text(response)
                            .textSelection(.enabled)
                    }
                }

                if let error = log.errorMessage {
                    GroupBox("错误") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
        }
    }
}
