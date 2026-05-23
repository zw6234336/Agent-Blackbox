import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject var database: DatabaseService

    var body: some View {
        DashboardView()
    }
}
