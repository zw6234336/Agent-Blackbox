import Foundation

struct InsuranceWorkspaceData {
    let householdName: String
    let conclusion: String
    let nextStep: String
    let protectionScore: Int
    let pendingMaterialCount: Int
    let annualBudget: Int
    let members: [FamilyMemberProfile]
    let readinessSteps: [ReadinessStep]
    let keyGaps: [CoverageGap]
    let actions: [ActionChecklistItem]
    let recommendations: [CoverageRecommendation]
    let products: [ComparedProduct]
    let knowledgeCards: [KnowledgeCard]

    var totalPolicies: Int {
        members.reduce(0) { $0 + $1.policies.count }
    }

    var totalAnnualPremium: Int {
        members.flatMap(\.policies).reduce(0) { $0 + $1.annualPremium }
    }

    var completedReadinessCount: Int {
        readinessSteps.filter(\.isComplete).count
    }

    var primaryRecommendation: CoverageRecommendation? {
        recommendations.first
    }

    static let sample = InsuranceWorkspaceData(
        householdName: "周先生家庭",
        conclusion: "你的医疗保障基础较完整，但家庭收入保障和重疾保障还有明显缺口。",
        nextStep: "优先补齐家庭经济支柱的定期寿险，其次优化重疾保额，再补充高免赔额医疗责任。",
        protectionScore: 74,
        pendingMaterialCount: 3,
        annualBudget: 18000,
        members: [
            FamilyMemberProfile(
                name: "周先生",
                role: .selfUser,
                age: 34,
                annualIncome: 420000,
                keyConcern: "家庭主要收入来源，寿险与重疾责任需要拉高。",
                policies: [
                    InsurancePolicy(
                        insurer: "平安健康",
                        name: "e 生保长期医疗",
                        category: .medical,
                        insuredAmount: 2000000,
                        annualPremium: 2860,
                        coveragePeriod: "1 年续保",
                        effectiveRule: "等待期 30 天",
                        sourceSummary: "条款结构化：住院医疗/特药责任已整理"
                    ),
                    InsurancePolicy(
                        insurer: "国联人寿",
                        name: "达尔文重疾险",
                        category: .criticalIllness,
                        insuredAmount: 300000,
                        annualPremium: 4680,
                        coveragePeriod: "保至 70 岁",
                        effectiveRule: "等待期 90 天",
                        sourceSummary: "条款结构化：重疾/中症/轻症责任已整理"
                    )
                ],
                gaps: [
                    CoverageGap(
                        category: .life,
                        currentAmount: 0,
                        targetAmount: 1500000,
                        explanation: "按 3-5 年家庭收入缺口测算，当前缺少身故/全残收入替代。",
                        source: "家庭收入规则 + 成员档案"
                    ),
                    CoverageGap(
                        category: .criticalIllness,
                        currentAmount: 300000,
                        targetAmount: 500000,
                        explanation: "现有 30 万保额不足以覆盖康复与收入损失。",
                        source: "重疾目标保额规则库"
                    )
                ]
            ),
            FamilyMemberProfile(
                name: "李女士",
                role: .spouse,
                age: 32,
                annualIncome: 240000,
                keyConcern: "医疗责任较好，意外与长期护理配置偏薄。",
                policies: [
                    InsurancePolicy(
                        insurer: "众安保险",
                        name: "尊享 e 生",
                        category: .medical,
                        insuredAmount: 1000000,
                        annualPremium: 1320,
                        coveragePeriod: "1 年续保",
                        effectiveRule: "等待期 30 天",
                        sourceSummary: "费率表已匹配 32 岁女性档"
                    ),
                    InsurancePolicy(
                        insurer: "中国人保",
                        name: "综合意外险",
                        category: .accident,
                        insuredAmount: 500000,
                        annualPremium: 620,
                        coveragePeriod: "1 年",
                        effectiveRule: "意外责任次日生效",
                        sourceSummary: "产品费率与免责摘要已整理"
                    )
                ],
                gaps: [
                    CoverageGap(
                        category: .longTermCare,
                        currentAmount: 0,
                        targetAmount: 300000,
                        explanation: "家庭需要补足中长期失能后的照护预算。",
                        source: "家庭责任模型"
                    )
                ]
            ),
            FamilyMemberProfile(
                name: "周小朋友",
                role: .child,
                age: 6,
                annualIncome: 0,
                keyConcern: "少儿医疗到位，重疾与门诊责任可继续增强。",
                policies: [
                    InsurancePolicy(
                        insurer: "支付宝少儿保",
                        name: "少儿门急诊医疗",
                        category: .medical,
                        insuredAmount: 100000,
                        annualPremium: 890,
                        coveragePeriod: "1 年",
                        effectiveRule: "疾病门诊等待期 30 天",
                        sourceSummary: "门急诊责任结构化完成"
                    )
                ],
                gaps: [
                    CoverageGap(
                        category: .criticalIllness,
                        currentAmount: 0,
                        targetAmount: 500000,
                        explanation: "儿童重疾治疗周期长，建议尽早锁定长期保额。",
                        source: "儿童保障目标规则"
                    )
                ]
            ),
            FamilyMemberProfile(
                name: "周妈妈",
                role: .parent,
                age: 58,
                annualIncome: 0,
                keyConcern: "年龄较高，更适合关注医疗、意外医疗和护理责任。",
                policies: [
                    InsurancePolicy(
                        insurer: "惠民保",
                        name: "城市惠民保",
                        category: .medical,
                        insuredAmount: 1500000,
                        annualPremium: 159,
                        coveragePeriod: "1 年",
                        effectiveRule: "社保目录内外医疗责任",
                        sourceSummary: "基础保障，免责限制较多"
                    )
                ],
                gaps: [
                    CoverageGap(
                        category: .accidentMedical,
                        currentAmount: 20000,
                        targetAmount: 100000,
                        explanation: "骨折、跌倒等高频风险的门急诊和住院自费段不足。",
                        source: "老人高频风险清单"
                    )
                ]
            )
        ],
        readinessSteps: [
            ReadinessStep(title: "资料接入", detail: "保单、家庭成员信息、预算已录入", isComplete: true),
            ReadinessStep(title: "知识结构化", detail: "已抽取 8 份条款责任、免责与等待期", isComplete: true),
            ReadinessStep(title: "保障分析", detail: "按成员、风险、责任完成缺口测算", isComplete: true),
            ReadinessStep(title: "缺口推荐", detail: "还需确认寿险预算与孩子重疾期限偏好", isComplete: false)
        ],
        keyGaps: [
            CoverageGap(
                category: .life,
                currentAmount: 0,
                targetAmount: 1500000,
                explanation: "家庭经济支柱缺少收入替代型保障。",
                source: "收入保障模型"
            ),
            CoverageGap(
                category: .criticalIllness,
                currentAmount: 300000,
                targetAmount: 1000000,
                explanation: "夫妻二人的重疾总保额不足，康复期资金压力较大。",
                source: "重疾目标保额规则"
            ),
            CoverageGap(
                category: .longTermCare,
                currentAmount: 0,
                targetAmount: 300000,
                explanation: "父母与配偶的长期护理预算尚未覆盖。",
                source: "家庭照护场景分析"
            )
        ],
        actions: [
            ActionChecklistItem(title: "补录寿险偏好", detail: "确定保至 60 岁还是 70 岁", isUrgent: true),
            ActionChecklistItem(title: "核对孩子已有少儿医保", detail: "补充门诊、住院报销比例", isUrgent: false),
            ActionChecklistItem(title: "确认家庭可接受年保费区间", detail: "基础版 / 均衡版 / 加强版方案会据此排序", isUrgent: false)
        ],
        recommendations: [
            CoverageRecommendation(
                title: "先补定期寿险，优先覆盖家庭收入风险",
                summary: "周先生目前缺少身故/全残责任，一旦发生风险，房贷与家庭生活开支将直接暴露。",
                whyNow: "家庭现金流主要来自你本人，寿险是当前最具杠杆的保障动作。",
                gapAmount: 1500000,
                estimatedAnnualPremium: 4200,
                improvement: "家庭收入保障完整度预计从 18% 提升到 86%",
                focusAction: "先补 150 万定期寿险，再根据预算决定是否延长保障期",
                plans: [
                    RecommendationPlan(tier: "基础版", annualPremium: 2600, addedCoverage: "100 万定期寿险", coverageLift: "收入责任提升到 62%", fitReason: "预算敏感，先把最核心缺口补上"),
                    RecommendationPlan(tier: "均衡版", annualPremium: 4200, addedCoverage: "150 万定期寿险", coverageLift: "收入责任提升到 86%", fitReason: "兼顾保额与保费，最适合作为主推方案"),
                    RecommendationPlan(tier: "加强版", annualPremium: 5600, addedCoverage: "200 万定期寿险", coverageLift: "收入责任提升到 100%", fitReason: "适合希望覆盖房贷和 5 年家庭支出的家庭")
                ]
            ),
            CoverageRecommendation(
                title: "重疾保额建议从 30 万提升到 50 万以上",
                summary: "夫妻双方目前重疾储备偏薄，尤其对康复期收入损失覆盖不足。",
                whyNow: "当前年龄段费率仍相对友好，尽快锁定长期保额更合适。",
                gapAmount: 200000,
                estimatedAnnualPremium: 3100,
                improvement: "重大疾病场景的资金储备提升约 40%",
                focusAction: "优先给周先生补 20 万重疾，再评估李女士是否补轻中症责任",
                plans: [
                    RecommendationPlan(tier: "基础版", annualPremium: 1800, addedCoverage: "加保 10 万重疾", coverageLift: "核心治疗预算更充足", fitReason: "先补刚性缺口，控制保费压力"),
                    RecommendationPlan(tier: "均衡版", annualPremium: 3100, addedCoverage: "加保 20 万重疾", coverageLift: "治疗 + 康复预算更均衡", fitReason: "适合有稳定现金流的三口之家"),
                    RecommendationPlan(tier: "加强版", annualPremium: 4600, addedCoverage: "夫妻分别加保 20 万", coverageLift: "双收入家庭风险同步提升", fitReason: "适合希望整体拉齐保障水平的家庭")
                ]
            ),
            CoverageRecommendation(
                title: "补足老人意外医疗与护理责任",
                summary: "周妈妈已有惠民保，但高频意外医疗和长期照护费用仍缺少明确安排。",
                whyNow: "父母年龄越大，可选产品越少，优先完善医疗边角责任更现实。",
                gapAmount: 380000,
                estimatedAnnualPremium: 1280,
                improvement: "父母场景的突发支出缓冲显著增强",
                focusAction: "先补意外医疗，再视预算增加长期护理金",
                plans: [
                    RecommendationPlan(tier: "基础版", annualPremium: 680, addedCoverage: "10 万意外医疗", coverageLift: "覆盖常见跌倒骨折住院", fitReason: "低预算也能快速见效"),
                    RecommendationPlan(tier: "均衡版", annualPremium: 1280, addedCoverage: "10 万意外医疗 + 15 万护理", coverageLift: "住院与护理费用一起补", fitReason: "适合希望兼顾老人照护的家庭"),
                    RecommendationPlan(tier: "加强版", annualPremium: 2200, addedCoverage: "20 万意外医疗 + 30 万护理", coverageLift: "老年风险覆盖更完整", fitReason: "适合有明确赡养预算规划的家庭")
                ]
            )
        ],
        products: [
            ComparedProduct(
                name: "定海柱 6 号",
                insurer: "华贵人寿",
                category: .life,
                annualPremiumText: "约 4200 元/年",
                suitability: "34 岁家庭经济支柱",
                benefits: ["150 万保额可覆盖房贷与 4 年家庭支出", "免责条款相对清晰", "可选保至 60/70 岁"],
                limitations: ["健康告知较严格", "等待期内责任有限"],
                fitReason: "最符合你当前“先补收入风险”的动作建议"
            ),
            ComparedProduct(
                name: "超级玛丽 11 号",
                insurer: "君龙人寿",
                category: .criticalIllness,
                annualPremiumText: "约 3100 元/年",
                suitability: "想补足 20 万重疾的人群",
                benefits: ["重疾基础责任清晰", "中轻症灵活", "适合当前年龄段加保"],
                limitations: ["长期责任组合较多，需注意保费变化", "部分附加责任等待期较长"],
                fitReason: "用较低增量保费补齐当前最明显的重疾缺口"
            ),
            ComparedProduct(
                name: "孝欣保中老年意外",
                insurer: "人保财险",
                category: .accidentMedical,
                annualPremiumText: "约 680 元/年",
                suitability: "55-65 岁父母辈",
                benefits: ["意外医疗责任直接", "骨折、救护车等场景更实用", "投保门槛较低"],
                limitations: ["不解决长期护理全额预算", "续保仍需关注年龄限制"],
                fitReason: "适合作为母亲当前最优先的边角责任补充"
            )
        ],
        knowledgeCards: [
            KnowledgeCard(title: "保什么", summary: "将重疾、医疗、寿险、意外与护理责任拆成用户能理解的五类责任", detail: "每张保单都会提炼出责任范围、保额、生效时间与主要限制，而不是原样堆条款。"),
            KnowledgeCard(title: "不保什么", summary: "重点呈现免责、等待期、赔付门槛", detail: "让推荐方案里的结论都能回溯到条款来源，减少“买了却赔不了”的误解。"),
            KnowledgeCard(title: "多少钱换来多少提升", summary: "费率信息嵌入方案，不单独展示算费表", detail: "用户更容易理解“多花 3000 元，家庭收入保障提升 24%”这样的表达。")
        ]
    )
}

enum FamilyRole: String {
    case selfUser = "本人"
    case spouse = "配偶"
    case child = "孩子"
    case parent = "父母"
}

enum CoverageCategory: String, CaseIterable, Identifiable {
    case life = "寿险"
    case criticalIllness = "重疾"
    case medical = "医疗"
    case accident = "意外"
    case accidentMedical = "意外医疗"
    case hospitalization = "住院津贴"
    case longTermCare = "长期护理"
    case familyLiability = "家庭责任"

    var id: String { rawValue }

    var shortDescription: String {
        switch self {
        case .life: return "收入替代"
        case .criticalIllness: return "治疗与康复"
        case .medical: return "住院与特药"
        case .accident: return "意外身故/伤残"
        case .accidentMedical: return "门急诊与住院自费"
        case .hospitalization: return "住院补贴"
        case .longTermCare: return "失能照护"
        case .familyLiability: return "家庭公共责任"
        }
    }
}

struct FamilyMemberProfile: Identifiable {
    private enum ScoreModel {
        static let emptyPolicyBaseline = 42.0
        static let insuredBaseline = 62.0
        static let ratioWeight = 28.0
        static let maxScore = 96
    }

    let id = UUID()
    let name: String
    let role: FamilyRole
    let age: Int
    let annualIncome: Int
    let keyConcern: String
    let policies: [InsurancePolicy]
    let gaps: [CoverageGap]

    var protectionScore: Int {
        let totalGapRatio = gaps.map(\.coverageRatio).reduce(0, +)
        let baseline = policies.isEmpty ? ScoreModel.emptyPolicyBaseline : ScoreModel.insuredBaseline
        let averageRatio = gaps.isEmpty ? 1.0 : totalGapRatio / Double(gaps.count)
        let weightedScore = baseline + averageRatio * ScoreModel.ratioWeight
        return min(ScoreModel.maxScore, Int(weightedScore.rounded()))
    }
}

struct InsurancePolicy: Identifiable {
    let id = UUID()
    let insurer: String
    let name: String
    let category: CoverageCategory
    let insuredAmount: Int
    let annualPremium: Int
    let coveragePeriod: String
    let effectiveRule: String
    let sourceSummary: String
}

struct CoverageGap: Identifiable {
    let id = UUID()
    let category: CoverageCategory
    let currentAmount: Int
    let targetAmount: Int
    let explanation: String
    let source: String

    var gapAmount: Int {
        max(0, targetAmount - currentAmount)
    }

    var coverageRatio: Double {
        guard targetAmount > 0 else { return 1 }
        return min(1, Double(currentAmount) / Double(targetAmount))
    }
}

struct ReadinessStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isComplete: Bool
}

struct ActionChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isUrgent: Bool
}

struct CoverageRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let whyNow: String
    let gapAmount: Int
    let estimatedAnnualPremium: Int
    let improvement: String
    let focusAction: String
    let plans: [RecommendationPlan]
}

struct RecommendationPlan: Identifiable {
    let id = UUID()
    let tier: String
    let annualPremium: Int
    let addedCoverage: String
    let coverageLift: String
    let fitReason: String
}

struct ComparedProduct: Identifiable {
    let id = UUID()
    let name: String
    let insurer: String
    let category: CoverageCategory
    let annualPremiumText: String
    let suitability: String
    let benefits: [String]
    let limitations: [String]
    let fitReason: String
}

struct KnowledgeCard: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let detail: String
}

/// Formats amounts for the current Chinese-language prototype UI.
/// Amounts below 10,000 are returned as "N 元" (for example, "5000 元").
/// Amounts at or above 10,000 are returned as "N 万" or "N.N 万" (for example, "1.5 万").
func formatInsuranceAmountCN(_ amount: Int) -> String {
    if amount >= 10_000 {
        let wan = Double(amount) / 10_000
        if wan.rounded() == wan {
            return "\(Int(wan)) 万"
        }
        return String(format: "%.1f 万", wan)
    }
    return "\(amount) 元"
}
