import Foundation
import Security

/// API Key 的存放处。
///
/// PRD 铁律：Key 只进 Keychain，绝不落到 UserDefaults、配置文件或日志里。
/// 用 `kSecClassGenericPassword` + 固定 service 前缀，每个 provider 一条记录。
///
/// - Note: 不开沙盒，所以用的是登录钥匙串，不需要 keychain-access-group 授权。
public struct KeychainStore: Sendable {

    /// 钥匙串里的 service 名。用 Bundle ID 前缀避免和别的 App 撞车。
    static let service = "com.chenya.yugit.ai"

    public init() {}

    /// 写入或覆盖一个 Key。
    ///
    /// 先删后写而不是 `SecItemUpdate`：更新路径要区分「已存在」和「不存在」两种情况，
    /// 而删除一个不存在的项是无害的，先删后加的分支更少也更难写错。
    public func store(_ key: String, for account: String) throws {
        try remove(for: account)

        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // 只在本机解锁后可用，且不参与 iCloud 钥匙串同步——
            // 用户的 API Key 没有理由离开这台机器。
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
    }

    /// 读取一个 Key，没有就返回 nil。
    public func key(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.operationFailed(status)
        }
    }

    /// 删除一个 Key。不存在时不算失败。
    public func remove(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }
}

public enum KeychainError: Error, Sendable, Equatable {
    case invalidData
    case operationFailed(OSStatus)

    public var localizedMessage: String {
        switch self {
        case .invalidData:
            return "钥匙串里的数据格式不对"
        case let .operationFailed(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "错误码 \(status)"
            return "钥匙串操作失败：\(detail)"
        }
    }
}
