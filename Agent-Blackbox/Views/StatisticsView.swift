import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var database: DatabaseService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日志统计")
                .font(.title2)
            Text("总日志数: \(database.logs.count)")
            Text("含错误日志: \(database.logs.filter { $0.errorMessage != nil }.count)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
