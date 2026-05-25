import Foundation
@preconcurrency import UserNotifications
import Combine

struct KeychainHelper {
    static let service = "com.agent-blackbox.keys"
    
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            // Fallback to UserDefaults if Keychain fails (e.g. sandbox or missing entitlements)
            UserDefaults.standard.set(value, forKey: "fallback_key_\(key)")
        }
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        // Try fallback
        return UserDefaults.standard.string(forKey: "fallback_key_\(key)")
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fallback_key_\(key)")
    }
}

// DeepSeek response models
struct DeepSeekBalanceResponse: Codable {
    let is_available: Bool
    let balance_infos: [DeepSeekBalanceInfo]
}

struct DeepSeekBalanceInfo: Codable {
    let currency: String
    let total_balance: String
    let granted_balance: String
    let topped_up_balance: String
}

// OpenRouter response models
struct OpenRouterKeyResponse: Codable {
    struct KeyData: Codable {
        let label: String
        let limit: Double?
        let usage: Double?
        let limit_remaining: Double?
        let is_free_tier: Bool?
    }
    let data: KeyData
}

@MainActor
final class KeyBalanceService: ObservableObject {
    @Published var deepSeekBalance: String = "未配置"
    @Published var openRouterBalance: String = "未配置"
    @Published var openRouterUsage: String = "0.00"
    
    @Published var isFetching = false
    @Published var errorMessage: String? = nil
    
    private var timer: Timer?
    
    // Save keys securely
    func saveDeepSeekKey(_ key: String) {
        if key.isEmpty {
            KeychainHelper.delete(key: "deepseek")
            deepSeekBalance = "未配置"
        } else {
            KeychainHelper.save(key: "deepseek", value: key)
            Task { await refreshBalances() }
        }
    }
    
    func saveOpenRouterKey(_ key: String) {
        if key.isEmpty {
            KeychainHelper.delete(key: "openrouter")
            openRouterBalance = "未配置"
            openRouterUsage = "0.00"
        } else {
            KeychainHelper.save(key: "openrouter", value: key)
            Task { await refreshBalances() }
        }
    }
    
    func getDeepSeekKey() -> String {
        return KeychainHelper.load(key: "deepseek") ?? ""
    }
    
    func getOpenRouterKey() -> String {
        return KeychainHelper.load(key: "openrouter") ?? ""
    }
    
    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshBalances()
            }
        }
        Task { await refreshBalances() }
    }
    
    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
    
    func refreshBalances() async {
        guard !isFetching else { return }
        isFetching = true
        errorMessage = nil
        
        let dsKey = getDeepSeekKey()
        let orKey = getOpenRouterKey()
        
        if dsKey.isEmpty && orKey.isEmpty {
            isFetching = false
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            if !dsKey.isEmpty {
                group.addTask {
                    await self.fetchDeepSeekBalance(key: dsKey)
                }
            }
            if !orKey.isEmpty {
                group.addTask {
                    await self.fetchOpenRouterBalance(key: orKey)
                }
            }
        }
        
        isFetching = false
    }
    
    private func fetchDeepSeekBalance(key: String) async {
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { self.deepSeekBalance = "网络错误" }
                return
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let result = try decoder.decode(DeepSeekBalanceResponse.self, from: data)
                if let info = result.balance_infos.first {
                    let formatted = "\(info.total_balance) \(info.currency)"
                    await MainActor.run {
                        self.deepSeekBalance = formatted
                        // Check alert threshold (e.g. below 10 CNY)
                        if let val = Double(info.total_balance), val < 10.0 {
                            self.sendLowBalanceNotification(platform: "DeepSeek", balance: formatted)
                        }
                    }
                } else {
                    await MainActor.run { self.deepSeekBalance = "解析失败" }
                }
            } else {
                await MainActor.run { self.deepSeekBalance = "Key 无效 (\(httpResponse.statusCode))" }
            }
        } catch {
            await MainActor.run { self.deepSeekBalance = "获取失败" }
        }
    }
    
    private func fetchOpenRouterBalance(key: String) async {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { self.openRouterBalance = "网络错误" }
                return
            }
            
            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let result = try decoder.decode(OpenRouterKeyResponse.self, from: data)
                await MainActor.run {
                    if let limit = result.data.limit, let usage = result.data.usage {
                        let remaining = max(0, limit - usage)
                        self.openRouterBalance = String(format: "$%.2f / $%.2f", remaining, limit)
                        self.openRouterUsage = String(format: "$%.2f", usage)
                        if remaining < 2.0 {
                            self.sendLowBalanceNotification(platform: "OpenRouter", balance: String(format: "$%.2f", remaining))
                        }
                    } else if let usage = result.data.usage {
                        // Pay as you go / Unlimited key
                        self.openRouterUsage = String(format: "$%.2f", usage)
                        if let remaining = result.data.limit_remaining {
                            self.openRouterBalance = String(format: "$%.2f", remaining)
                            if remaining < 2.0 {
                                self.sendLowBalanceNotification(platform: "OpenRouter", balance: String(format: "$%.2f", remaining))
                            }
                        } else {
                            self.openRouterBalance = "无限额 / 按量扣费"
                        }
                    } else {
                        self.openRouterBalance = "获取成功"
                    }
                }
            } else {
                await MainActor.run { self.openRouterBalance = "Key 无效 (\(httpResponse.statusCode))" }
            }
        } catch {
            await MainActor.run { self.openRouterBalance = "获取失败" }
        }
    }
    
    private func sendLowBalanceNotification(platform: String, balance: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "🚨 \(platform) 账户余额不足警告"
            content.body = "您的 \(platform) 剩余额度仅剩 \(balance)，请及时充值以免影响 AI 编码助手的使用。"
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: "low_balance_\(platform)", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
