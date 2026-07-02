import Foundation
import Security

/// Generic password 类型的 Keychain 包装。
/// App Sandbox 里也能用，存 API key 这类敏感字符串。
/// 用法：
///   KeychainService.shared.set("sk-xxx", account: "openai")
///   KeychainService.shared.get(account: "openai")
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
            if addStatus != errSecSuccess {
                NSLog("[KeychainService] set add failed status=\(addStatus)")
            }
            return addStatus == errSecSuccess
        }
        NSLog("[KeychainService] set update failed status=\(updateStatus)")
        return false
    }

    /// Read result, distinguishes "not found" / "locked" / "found" / "other error".
    /// Callers can use this to decide whether to retry, clear stale flags, etc.
    /// (Previously the API returned String? which silently swallowed errSecItemNotFound
    /// AND errSecInteractionNotAllowed, making them indistinguishable.)
    enum GetResult: Equatable {
        case found(String)
        case notFound                  // errSecItemNotFound — no key stored
        case locked                    // errSecInteractionNotAllowed — keychain locked
        case other(OSStatus)           // unexpected status, logged
    }

    func get(account: String) -> GetResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                NSLog("[KeychainService] get: success but decode failed")
                return .other(status)
            }
            return .found(str)
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed:
            NSLog("[KeychainService] get: keychain locked (errSecInteractionNotAllowed)")
            return .locked
        default:
            NSLog("[KeychainService] get failed status=\(status)")
            return .other(status)
        }
    }

    /// Convenience: returns the value or nil, treating all error cases as nil.
    /// Use `get(account:)` if you need to distinguish not-found from locked.
    func getValue(account: String) -> String? {
        if case .found(let v) = get(account: account) { return v }
        return nil
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
