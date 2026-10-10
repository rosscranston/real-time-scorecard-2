import Foundation
import Security
import LocalAuthentication

public enum CredentialStore {
    private static let operationLock = NSLock()
    private static let service = "ai.cranston.live-scorecard-2"
    private static let account = "openai-api-key"
    public static func save(_ key: String) throws {
        operationLock.lock(); defer { operationLock.unlock() }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isWhitespace) else { throw OpenAIError.missingKey }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        let update = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(key.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DatabaseError(message: "Keychain could not save the key (status \(status)).") }
    }
    public static func load(allowInteraction: Bool = true) throws -> String? {
        operationLock.lock(); defer { operationLock.unlock() }
        // Ad-hoc macOS builds use the file-based Keychain. LAContext alone does
        // not suppress its ACL prompts, so preserve/restore the legacy process
        // flag inside the same lock used by all credential operations.
        var previousInteraction: DarwinBoolean = true
        var changedInteraction = false
        if !allowInteraction {
            let readStatus = SecKeychainGetUserInteractionAllowed(&previousInteraction)
            guard readStatus == errSecSuccess else {
                throw DatabaseError(message: "Cannot check Keychain authorization. Try Test text APIs in Settings.")
            }
            let status = SecKeychainSetUserInteractionAllowed(false)
            guard status == errSecSuccess else {
                throw DatabaseError(message: "Cannot read Keychain without authorization. Try Test text APIs in Settings.")
            }
            changedInteraction = true
        }
        defer {
            if changedInteraction { SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
        }
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            throw DatabaseError(message: "Saved key needs macOS authorization. Open Settings and choose Test text APIs, then approve the Keychain prompt.")
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DatabaseError(message: "Keychain could not read the key (status \(status)).")
        }
        return String(data: data, encoding: .utf8)
    }
    public static func remove() throws {
        operationLock.lock(); defer { operationLock.unlock() }
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DatabaseError(message: "Keychain could not remove the key (status \(status)).")
        }
    }
    public static func developerKey(directory: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let value = environment["OPENAI_API_KEY"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        guard let directory, let text = try? String(contentsOf: directory.appendingPathComponent(".env"), encoding: .utf8) else { return nil }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == "OPENAI_API_KEY" {
                let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
