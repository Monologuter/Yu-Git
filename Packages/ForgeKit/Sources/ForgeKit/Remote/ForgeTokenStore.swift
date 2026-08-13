import Foundation
import Security

/// 平台访问令牌的存放处。
///
/// 和 AI 的 API Key 同一条规矩：只进 Keychain，不落配置文件，不参与 iCloud 同步。
/// **按主机名索引**而不是按平台种类——同一个人可能同时有 github.com 的令牌
/// 和公司自建 GitLab 的令牌，两者互不相干。
public struct ForgeTokenStore: Sendable {

    static let service = "com.chenya.yugit.forge"

    public init() {}

    public func store(_ token: String, forHost host: String) throws {
        try remove(forHost: host)

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let data = trimmed.data(using: .utf8) else {
            throw ForgeTokenError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host.lowercased(),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ForgeTokenError.operationFailed(status) }
    }

    public func token(forHost host: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host.lowercased(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw ForgeTokenError.invalidData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw ForgeTokenError.operationFailed(status)
        }
    }

    public func remove(forHost host: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host.lowercased(),
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ForgeTokenError.operationFailed(status)
        }
    }

    /// 已经配过令牌的主机名。
    public func configuredHosts() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        switch status {
        case errSecSuccess:
            let entries = items as? [[String: Any]] ?? []
            return entries.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
        case errSecItemNotFound:
            return []
        default:
            throw ForgeTokenError.operationFailed(status)
        }
    }
}

public enum ForgeTokenError: Error, Sendable, Equatable {
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
