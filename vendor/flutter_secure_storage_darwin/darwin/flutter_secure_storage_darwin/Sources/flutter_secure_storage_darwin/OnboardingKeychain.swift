import Foundation
import Security

/// Injectable native Security calls. There is deliberately no delete operation.
struct OnboardingKeychainAccess {
    var lookup: ([CFString: Any]) -> (OSStatus, Data?)
    var update: ([CFString: Any], [CFString: Any]) -> OSStatus
    var add: ([CFString: Any]) -> OSStatus

    static let live = OnboardingKeychainAccess(
        lookup: { query in
            var reference: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &reference)
            return (status, reference as? Data)
        },
        update: { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) },
        add: { SecItemAdd($0 as CFDictionary, nil) }
    )
}

enum OnboardingKeychain {
    static func withoutReturnOptions(_ query: [CFString: Any]) -> [CFString: Any] {
        var clean = query
        for key in [kSecReturnData, kSecReturnAttributes, kSecReturnRef, kSecReturnPersistentRef, kSecMatchLimit] {
            clean.removeValue(forKey: key)
        }
        return clean
    }

    /// Update the actual item found, including legacy envelopes, without changing
    /// its identity/accessibility. Only confirmed absence permits an add.
    static func write(queries: [[CFString: Any]], addQuery: [CFString: Any],
                      data: Data, access: OnboardingKeychainAccess = .live) -> OSStatus {
        func updateExisting() -> (found: Bool, status: OSStatus) {
            for candidate in queries {
                var lookup = withoutReturnOptions(candidate)
                lookup[kSecReturnPersistentRef] = true
                lookup[kSecMatchLimit] = kSecMatchLimitOne
                let (status, reference) = access.lookup(lookup)
                if status == errSecItemNotFound { continue }
                guard status == errSecSuccess else { return (true, status) }
                guard let reference = reference else { return (true, errSecDecode) }
                var updateQuery: [CFString: Any] = [kSecValuePersistentRef: reference]
                #if os(macOS)
                updateQuery[kSecUseDataProtectionKeychain] = candidate[kSecUseDataProtectionKeychain]
                #endif
                return (true, access.update(updateQuery, [kSecValueData: data]))
            }
            return (false, errSecItemNotFound)
        }
        let existing = updateExisting()
        if existing.found { return existing.status }
        var add = withoutReturnOptions(addQuery)
        add[kSecValueData] = data
        let status = access.add(add)
        guard status == errSecDuplicateItem else { return status }
        // A concurrent creator won. Resolve once and update that item; never
        // delete it or loop indefinitely, and propagate lookup/update errors.
        let raced = updateExisting()
        return raced.found ? raced.status : errSecDuplicateItem
    }
}
