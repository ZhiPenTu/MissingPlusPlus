import Foundation
import Security

/// Generic password 类型的 Keychain 包装。
/// App Sandbox 里也能用，存 API key 这类敏感字符串。
/// 用法：
///   KeychainService.shared.set("sk-xxx", account: "openai")
///   KeychainService.shared.get(account: "openai")  // -> String?
///   KeychainService.shared.delete(account: "openai")
///
/// service 用 bundle id 反向域（kSecAttrService 限制为 plain ASCII），
/// account 用来区分同一 service 下多个 key（目前只有 openai，留扩展）。
final class KeychainService {
    static let shared = KeychainService()

    /// 反向域 ASCII 形式，kSecAttrService 不接受非 ASCII / 空。
    private let service: String = "com.tuzhipeng.MissingPlusPlus"

    private init() {}

    @discardableResult
    func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // 先尝试 update（key 已存在的常见情况）
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            // 不存在 → add
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        NSLog("[KeychainService] set update failed status=\(updateStatus)")
        return false
    }

    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                NSLog("[KeychainService] get failed status=\(status)")
            }
            return nil
        }
        return str
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
