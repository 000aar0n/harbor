import Cocoa
import Security

struct TunnelSettings: Codable {
    let endpoint: String
    let token: String
    var url: URL? {
        guard let u = URL(string: endpoint), u.scheme == "wss", u.host != nil,
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
              u.path == "/tunnel", token.count >= 32 else { return nil }
        return u
    }
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.harbor.browser.tunnel", kSecAttrAccount as String: "configuration"]
    static func load() -> TunnelSettings? {
        var q = query
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TunnelSettings.self, from: data)
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        var q = Self.query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        let status = result == errSecItemNotFound ? SecItemAdd(q as CFDictionary, nil) : result
        if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
