import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case dashboard
        case coverage
        case analysis
        case recommendations
        case comparison
    }

    @State private var selectedTab: Tab? = .dashboard // Optional selection is required by sidebar List selection on macOS.
    private let workspace = InsuranceWorkspaceData.sample

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("总览", systemImage: "house")
                    .tag(Tab.dashboard)
                Label("我的保障", systemImage: "person.2")
                    .tag(Tab.coverage)
                Label("保障分析", systemImage: "shield.checkered")
                    .tag(Tab.analysis)
                Label("缺口推荐", systemImage: "sparkles")
                    .tag(Tab.recommendations)
                Label("产品对比", systemImage: "square.grid.2x2")
                    .tag(Tab.comparison)
            }
            .navigationTitle("保险决策助手")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedTab ?? .dashboard {
                case .dashboard:
                    InsuranceDashboardView(workspace: workspace)
                case .coverage:
                    MyCoverageView(workspace: workspace)
                case .analysis:
                    GapAnalysisView(workspace: workspace)
                case .recommendations:
                    RecommendationsView(workspace: workspace)
                case .comparison:
                    ProductComparisonView(workspace: workspace)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Label("家庭保障分 \(workspace.protectionScore)", systemImage: "shield.lefthalf.filled")
                    Text("待补资料 \(workspace.pendingMaterialCount)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
