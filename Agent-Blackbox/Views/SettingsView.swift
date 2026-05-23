import SwiftUI

struct SettingsView: View {
    private static let designPrincipleDescription = "界面默认先展示结论、缺口和行动建议，不再以监控状态、底层日志或工程化配置为主。"
    private let workspace = InsuranceWorkspaceData.sample

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("规划偏好")
                    .font(.title2)
                    .fontWeight(.semibold)

                preferenceCard(
                    title: "当前默认预算",
                    value: formatInsuranceAmountCN(workspace.annualBudget),
                    detail: "推荐页面会优先展示与此预算接近的基础版、均衡版、加强版方案。"
                )

                preferenceCard(
                    title: "资料完整度",
                    value: "\(workspace.completedReadinessCount)/\(workspace.readinessSteps.count) 步",
                    detail: "资料接入、知识结构化、保障分析已经完成，仍有部分偏好待确认。"
                )

                preferenceCard(
                    title: "当前提醒",
                    value: "\(workspace.pendingMaterialCount) 项待完善",
                    detail: "建议优先补录寿险期限偏好、少儿医保信息和家庭年保费区间。"
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("产品设计原则")
                        .font(.headline)
                    Text(Self.designPrincipleDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 420)
    }

    private func preferenceCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05))
        )
    }
}
