import SwiftUI

private enum InsurancePalette {
    static let background = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let card = Color.white.opacity(0.92)
    static let primary = Color(red: 0.20, green: 0.42, blue: 0.57)
    static let accent = Color(red: 0.42, green: 0.63, blue: 0.55)
    static let warning = Color(red: 0.85, green: 0.56, blue: 0.32)
    static let softText = Color(red: 0.33, green: 0.37, blue: 0.40)
}

struct InsuranceDashboardView: View {
    let workspace: InsuranceWorkspaceData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeroCard(workspace: workspace)
                planningReadiness
                summaryMetrics
                keyGapSection
                actionSection
                knowledgeSection
            }
            .padding(24)
        }
        .background(InsurancePalette.background.ignoresSafeArea())
    }

    private var planningReadiness: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "规划进度", subtitle: "围绕资料接入、知识结构化、保障分析、缺口推荐形成完整闭环")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(workspace.readinessSteps) { step in
                    SoftCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                StatusPill(title: step.isComplete ? "已完成" : "待完善", tint: step.isComplete ? InsurancePalette.accent : InsurancePalette.warning)
                                Spacer()
                            }
                            Text(step.title)
                                .font(.headline)
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var summaryMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
            SummaryMetricCard(title: "家庭保障分", value: "\(workspace.protectionScore)", detail: "覆盖完整度" , tint: InsurancePalette.primary)
            SummaryMetricCard(title: "已整理保单", value: "\(workspace.totalPolicies)", detail: "含费率与条款摘要", tint: InsurancePalette.accent)
            SummaryMetricCard(title: "待补资料", value: "\(workspace.pendingMaterialCount)", detail: "还影响最终推荐", tint: InsurancePalette.warning)
            SummaryMetricCard(title: "当前年保费", value: formatInsuranceAmount(workspace.totalAnnualPremium), detail: "家庭已配置预算", tint: InsurancePalette.primary)
        }
    }

    private var keyGapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "最大缺口", subtitle: "只保留最影响决策的三类风险")
            ForEach(workspace.keyGaps) { gap in
                GapInsightRow(gap: gap)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "下一步行动", subtitle: "先完成少量高价值动作，再进入正式推荐")
            ForEach(workspace.actions) { item in
                SoftCard {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(item.isUrgent ? InsurancePalette.warning : InsurancePalette.accent)
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "条款与费率如何转成用户价值", subtitle: "只展示对决策真正有帮助的提炼结果")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                ForEach(workspace.knowledgeCards) { knowledge in
                    SoftCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(knowledge.title)
                                .font(.headline)
                            Text(knowledge.summary)
                                .font(.subheadline)
                            Text(knowledge.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct MyCoverageView: View {
    let workspace: InsuranceWorkspaceData
    @State private var selectedMemberID: FamilyMemberProfile.ID?

    private var selectedMember: FamilyMemberProfile {
        workspace.members.first(where: { $0.id == selectedMemberID }) ?? workspace.members[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(title: "我的保障", subtitle: "按家庭成员查看已配置保单、责任覆盖和关键缺口")
                memberSelector
                memberSummary
                policyList
                sourceFootnote
            }
            .padding(24)
        }
        .background(InsurancePalette.background.ignoresSafeArea())
        .onAppear {
            selectedMemberID = selectedMemberID ?? workspace.members.first?.id
        }
    }

    private var memberSelector: some View {
        HStack(spacing: 12) {
            ForEach(workspace.members) { member in
                Button {
                    selectedMemberID = member.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name)
                            .font(.headline)
                        Text(member.role.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedMemberID == member.id ? InsurancePalette.primary.opacity(0.16) : InsurancePalette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(selectedMemberID == member.id ? InsurancePalette.primary.opacity(0.45) : Color.black.opacity(0.05))
                    )
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var memberSummary: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(selectedMember.name) · \(selectedMember.role.rawValue)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("\(selectedMember.age) 岁")
                            .foregroundColor(.secondary)
                        Text(selectedMember.keyConcern)
                            .font(.subheadline)
                            .foregroundColor(InsurancePalette.softText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("保障分 \(selectedMember.protectionScore)")
                            .font(.headline)
                        Text(selectedMember.annualIncome == 0 ? "当前无收入" : "年收入 \(formatInsuranceAmount(selectedMember.annualIncome))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(selectedMember.gaps) { gap in
                    CoverageProgressRow(gap: gap)
                }
            }
        }
    }

    private var policyList: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "已录入保单", subtitle: "展示用户能看懂的保障字段，而不是原始条款")
            ForEach(selectedMember.policies) { policy in
                SoftCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(policy.name)
                                    .font(.headline)
                                Text("\(policy.insurer) · \(policy.category.rawValue)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(formatInsuranceAmount(policy.insuredAmount))
                                .font(.headline)
                                .foregroundColor(InsurancePalette.primary)
                        }
                        SimpleInfoLine(label: "保障期间", value: policy.coveragePeriod)
                        SimpleInfoLine(label: "生效规则", value: policy.effectiveRule)
                        SimpleInfoLine(label: "预计年保费", value: formatInsuranceAmount(policy.annualPremium))
                        SimpleInfoLine(label: "来源说明", value: policy.sourceSummary)
                    }
                }
            }
        }
    }

    private var sourceFootnote: some View {
        Text("所有结论都可回溯到保单条款摘要、费率档位和家庭成员资料，帮助用户理解“为什么这样分析”。")
            .font(.footnote)
            .foregroundColor(.secondary)
    }
}

struct GapAnalysisView: View {
    let workspace: InsuranceWorkspaceData

    private var groupedGaps: [CoverageGap] {
        workspace.keyGaps
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(title: "保障分析", subtitle: "按风险维度看覆盖情况，用卡片和进度替代复杂表格")
                SoftCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("一句话结论")
                            .font(.headline)
                        Text(workspace.conclusion)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("分析逻辑：已有保障 vs 建议目标保额，综合家庭角色、预算与高频风险场景后输出覆盖率与缺口金额。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(groupedGaps) { gap in
                    SoftCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gap.category.rawValue)
                                        .font(.headline)
                                    Text(gap.category.shortDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                StatusPill(title: "缺口 \(formatInsuranceAmount(gap.gapAmount))", tint: InsurancePalette.warning)
                            }
                            CoverageProgressBar(progress: gap.coverageRatio)
                            HStack {
                                Text("已覆盖 \(formatInsuranceAmount(gap.currentAmount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("建议目标 \(formatInsuranceAmount(gap.targetAmount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(gap.explanation)
                                .font(.subheadline)
                            Text("依据来源：\(gap.source)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(InsurancePalette.background.ignoresSafeArea())
    }
}

struct RecommendationsView: View {
    let workspace: InsuranceWorkspaceData
    @State private var selectedRecommendationID: CoverageRecommendation.ID?

    private var selectedRecommendation: CoverageRecommendation {
        workspace.recommendations.first(where: { $0.id == selectedRecommendationID }) ?? workspace.recommendations[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(title: "缺口推荐", subtitle: "先告诉用户最该补什么，再解释为什么、补多少、预算大概多少")
                recommendationSummary
                recommendationTabs
                planComparison
            }
            .padding(24)
        }
        .background(InsurancePalette.background.ignoresSafeArea())
        .onAppear {
            selectedRecommendationID = selectedRecommendationID ?? workspace.recommendations.first?.id
        }
    }

    private var recommendationSummary: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedRecommendation.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(selectedRecommendation.summary)
                    .font(.subheadline)
                HStack(spacing: 12) {
                    StatusPill(title: "缺口 \(formatInsuranceAmount(selectedRecommendation.gapAmount))", tint: InsurancePalette.warning)
                    StatusPill(title: "预计增量保费 \(formatInsuranceAmount(selectedRecommendation.estimatedAnnualPremium))", tint: InsurancePalette.primary)
                }
                SimpleInfoLine(label: "为什么现在优先", value: selectedRecommendation.whyNow)
                SimpleInfoLine(label: "推荐动作", value: selectedRecommendation.focusAction)
                SimpleInfoLine(label: "预期提升", value: selectedRecommendation.improvement)
            }
        }
    }

    private var recommendationTabs: some View {
        HStack(spacing: 12) {
            ForEach(workspace.recommendations) { recommendation in
                Button {
                    selectedRecommendationID = recommendation.id
                } label: {
                    Text(recommendation.title)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedRecommendationID == recommendation.id ? InsurancePalette.primary.opacity(0.14) : InsurancePalette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(selectedRecommendationID == recommendation.id ? InsurancePalette.primary.opacity(0.45) : Color.black.opacity(0.05))
                        )
                        .cornerRadius(18)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planComparison: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "三档方案", subtitle: "基础版、均衡版、加强版，方便用户按预算快速决策")
            ForEach(selectedRecommendation.plans) { plan in
                SoftCard {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(plan.tier)
                                .font(.headline)
                            Text(formatInsuranceAmount(plan.annualPremium))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(InsurancePalette.primary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            SimpleInfoLine(label: "新增保障", value: plan.addedCoverage)
                            SimpleInfoLine(label: "覆盖提升", value: plan.coverageLift)
                            SimpleInfoLine(label: "适合原因", value: plan.fitReason)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

struct ProductComparisonView: View {
    let workspace: InsuranceWorkspaceData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeader(title: "产品对比", subtitle: "只保留少量候选产品，并说明它为什么适合当前缺口")
                ForEach(workspace.products) { product in
                    SoftCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(product.name)
                                        .font(.headline)
                                    Text("\(product.insurer) · \(product.category.rawValue)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(product.annualPremiumText)
                                        .font(.headline)
                                        .foregroundColor(InsurancePalette.primary)
                                    Text(product.suitability)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ComparisonList(title: "适配亮点", items: product.benefits, tint: InsurancePalette.accent)
                            ComparisonList(title: "需要注意", items: product.limitations, tint: InsurancePalette.warning)
                            SimpleInfoLine(label: "适配原因", value: product.fitReason)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(InsurancePalette.background.ignoresSafeArea())
    }
}

private struct DashboardHeroCard: View {
    let workspace: InsuranceWorkspaceData

    var body: some View {
        SoftCard(background: LinearGradient(colors: [Color.white, InsurancePalette.primary.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(workspace.householdName)的保障总览")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(workspace.conclusion)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(InsurancePalette.softText)
                Text(workspace.nextStep)
                    .font(.title3)
                    .foregroundColor(.secondary)
                HStack(spacing: 16) {
                    HeroStat(title: "家庭保障分", value: "\(workspace.protectionScore)")
                    HeroStat(title: "年度预算参考", value: formatInsuranceAmount(workspace.annualBudget))
                    HeroStat(title: "规划完成度", value: "\(workspace.completedReadinessCount)/\(workspace.readinessSteps.count)")
                }
            }
        }
    }
}

private struct HeroStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(tint)
                    )
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct GapInsightRow: View {
    let gap: CoverageGap

    var body: some View {
        SoftCard {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(gap.category.rawValue)
                        .font(.headline)
                    Text(gap.explanation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatInsuranceAmount(gap.gapAmount))
                        .font(.headline)
                        .foregroundColor(InsurancePalette.warning)
                    Text("建议目标 \(formatInsuranceAmount(gap.targetAmount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct CoverageProgressRow: View {
    let gap: CoverageGap

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(gap.category.rawValue)
                    .font(.headline)
                Spacer()
                Text("缺口 \(formatInsuranceAmount(gap.gapAmount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            CoverageProgressBar(progress: gap.coverageRatio)
            Text(gap.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct CoverageProgressBar: View {
    let progress: Double

    var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(InsurancePalette.accent)
            .scaleEffect(x: 1, y: 1.5, anchor: .center)
    }
}

private struct ComparisonList: View {
    let title: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct SimpleInfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .foregroundColor(InsurancePalette.softText)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }
}

private struct SoftCard<Content: View>: View {
    var background: AnyShapeStyle = AnyShapeStyle(InsurancePalette.card)
    let content: Content

    init(background: some ShapeStyle = InsurancePalette.card, @ViewBuilder content: () -> Content) {
        self.background = AnyShapeStyle(background)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05))
        )
    }
}
