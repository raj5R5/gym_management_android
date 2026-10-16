import Foundation
import Security
import XCTest

final class OnboardingKeychainTests: XCTestCase {
    let key = "gym.onboarding.v1.test.scope.pending"
    let reference = Data([1, 2, 3])
    var queries: [[CFString: Any]] = []
    var updates = 0
    var adds = 0
    var item = Data("original-frozen-request-and-key".utf8)

    func parameters() -> KeychainQueryParameters {
        KeychainQueryParameters(key: key, service: "flutter_secure_storage_service",
            isSynchronizable: false, accessibilityLevel: "unlocked_this_device",
            usesDataProtectionKeychain: false, shouldReturnData: true)
    }

    func write(_ access: OnboardingKeychainAccess) -> OSStatus {
        FlutterSecureStorage().writeOnboarding(params: parameters(), value: "replacement", access: access).status
    }

    @objc func testSuccessfulUpdatePreservesIdentityAndRemovesReturnFlags() {
        let access = OnboardingKeychainAccess(lookup: { query in
            self.queries.append(query)
            XCTAssertEqual(query[kSecAttrAccount] as? String, self.key)
            XCTAssertEqual(query[kSecAttrService] as? String, "flutter_secure_storage_service")
            XCTAssertNil(query[kSecReturnData])
            return (errSecSuccess, self.reference)
        }, update: { query, attributes in
            self.updates += 1
            for key in [kSecReturnData, kSecReturnRef, kSecReturnAttributes, kSecReturnPersistentRef, kSecMatchLimit] {
                XCTAssertNil(query[key])
            }
            XCTAssertEqual(query[kSecValuePersistentRef] as? Data, self.reference)
            self.item = attributes[kSecValueData] as! Data
            return errSecSuccess
        }, add: { _ in self.adds += 1; return errSecSuccess })
        XCTAssertEqual(write(access), errSecSuccess)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(adds, 0)
        XCTAssertEqual(item, Data("replacement".utf8))
    }

    @objc func testFailedUpdateDoesNotDeleteOrAdd() {
        for failure in [errSecInteractionNotAllowed, errSecAuthFailed, errSecParam, errSecNotAvailable, errSecItemNotFound] {
            let original = item
            let access = OnboardingKeychainAccess(lookup: { _ in (errSecSuccess, self.reference) },
                update: { _, _ in failure }, add: { _ in self.adds += 1; self.item = Data(); return errSecSuccess })
            XCTAssertEqual(write(access), failure)
            XCTAssertEqual(item, original)
            XCTAssertEqual(adds, 0)
        }
    }

    @objc func testLookupFailureIsNotAbsence() {
        for failure in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecNotAvailable] {
            let access = OnboardingKeychainAccess(lookup: { _ in (failure, nil) },
                update: { _, _ in XCTFail("update after lookup failure"); return errSecSuccess },
                add: { _ in XCTFail("add after lookup failure"); return errSecSuccess })
            XCTAssertEqual(write(access), failure)
        }
    }

    @objc func testConfirmedAbsenceAddsWithOriginalAccessibilityAndIdentity() {
        let access = OnboardingKeychainAccess(lookup: { _ in (errSecItemNotFound, nil) },
            update: { _, _ in XCTFail("unexpected update"); return errSecSuccess }, add: { query in
                self.adds += 1
                XCTAssertEqual(query[kSecAttrAccount] as? String, self.key)
                XCTAssertEqual(query[kSecAttrService] as? String, "flutter_secure_storage_service")
                XCTAssertEqual(query[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
                XCTAssertNil(query[kSecReturnData])
                XCTAssertEqual(query[kSecValueData] as? Data, Data("replacement".utf8))
                return errSecSuccess
            })
        XCTAssertEqual(write(access), errSecSuccess)
        XCTAssertEqual(adds, 1)
    }

    @objc func testAddErrorIsPropagated() {
        let access = OnboardingKeychainAccess(lookup: { _ in (errSecItemNotFound, nil) },
            update: { _, _ in XCTFail("unexpected update"); return errSecSuccess }, add: { _ in errSecNotAvailable })
        XCTAssertEqual(write(access), errSecNotAvailable)
    }

    @objc func testDuplicateCreatorRaceUpdatesOnceWithoutDeletion() {
        var created = false
        let access = OnboardingKeychainAccess(lookup: { _ in created ? (errSecSuccess, self.reference) : (errSecItemNotFound, nil) },
            update: { _, _ in self.updates += 1; return errSecSuccess },
            add: { _ in self.adds += 1; created = true; return errSecDuplicateItem })
        XCTAssertEqual(write(access), errSecSuccess)
        XCTAssertEqual(adds, 1)
        XCTAssertEqual(updates, 1)
    }

    @objc func testDuplicateRaceUpdateFailurePreservesOriginal() {
        var created = false
        let original = item
        let access = OnboardingKeychainAccess(lookup: { _ in created ? (errSecSuccess, self.reference) : (errSecItemNotFound, nil) },
            update: { _, _ in self.updates += 1; return errSecInteractionNotAllowed },
            add: { _ in self.adds += 1; created = true; return errSecDuplicateItem })
        XCTAssertEqual(write(access), errSecInteractionNotAllowed)
        XCTAssertEqual(item, original)
        XCTAssertEqual(adds, 1)
        XCTAssertEqual(updates, 1)
    }

    @objc func testDuplicateRaceLookupFailurePropagates() {
        var created = false
        let access = OnboardingKeychainAccess(lookup: { _ in created ? (errSecNotAvailable, nil) : (errSecItemNotFound, nil) },
            update: { _, _ in XCTFail("unexpected update"); return errSecSuccess },
            add: { _ in created = true; return errSecDuplicateItem })
        XCTAssertEqual(write(access), errSecNotAvailable)
    }

    @objc func testUnresolvedDuplicateDoesNotLoop() {
        let access = OnboardingKeychainAccess(lookup: { _ in (errSecItemNotFound, nil) },
            update: { _, _ in XCTFail("unexpected update"); return errSecSuccess },
            add: { _ in self.adds += 1; return errSecDuplicateItem })
        XCTAssertEqual(write(access), errSecDuplicateItem)
        XCTAssertEqual(adds, 1)
    }

    @objc func testLegacyEnvelopeUpdatesActualItemWithoutRecreation() {
        let access = OnboardingKeychainAccess(lookup: { query in
            if query[kSecAttrAccessControl] != nil { return (errSecSuccess, self.reference) }
            return (errSecItemNotFound, nil)
        }, update: { query, _ in
            self.updates += 1
            XCTAssertEqual(query[kSecValuePersistentRef] as? Data, self.reference)
            XCTAssertNil(query[kSecAttrAccessible])
            return errSecSuccess
        }, add: { _ in XCTFail("legacy item recreated"); return errSecSuccess })
        XCTAssertEqual(write(access), errSecSuccess)
        XCTAssertEqual(updates, 1)
    }

    @objc func testDifferentAccessibilityRetainedWithoutMigration() {
        let access = OnboardingKeychainAccess(lookup: { query in
            if query[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String {
                return (errSecSuccess, self.reference)
            }
            return (errSecItemNotFound, nil)
        }, update: { query, attrs in
            XCTAssertEqual(query[kSecValuePersistentRef] as? Data, self.reference)
            XCTAssertEqual(attrs.count, 1) // No accessibility mutation.
            return errSecSuccess
        }, add: { _ in XCTFail("existing item recreated"); return errSecSuccess })
        XCTAssertEqual(write(access), errSecSuccess)
    }

    @objc func testMalformedLookupResultFailsClosed() {
        let access = OnboardingKeychainAccess(lookup: { _ in (errSecSuccess, nil) },
            update: { _, _ in XCTFail("unexpected update"); return errSecSuccess },
            add: { _ in XCTFail("unexpected add"); return errSecSuccess })
        XCTAssertEqual(write(access), errSecDecode)
    }

    @objc func testPaymentRecoveryUsesNonDestructiveUpdate() {
        var params = parameters(); params.key = "gym.payment.v1.test.scope.pending"
        let access = OnboardingKeychainAccess(lookup: { query in
            XCTAssertEqual(query[kSecAttrAccount] as? String, params.key)
            return (errSecSuccess, self.reference)
        }, update: { query, _ in
            XCTAssertEqual(query[kSecValuePersistentRef] as? Data, self.reference)
            return errSecInteractionNotAllowed
        }, add: { _ in XCTFail("failed payment replacement must not add"); return errSecSuccess })
        let original = item
        XCTAssertEqual(FlutterSecureStorage().writeOnboarding(params: params,
            value: "payment-replacement", access: access).status, errSecInteractionNotAllowed)
        XCTAssertEqual(item, original)
    }

    @objc func testAuthenticationKeyCannotUseNewMethod() {
        var params = parameters(); params.key = "authentication.refresh"
        XCTAssertEqual(FlutterSecureStorage().writeOnboarding(params: params, value: "synthetic").status, errSecParam)
    }

}
let suite = OnboardingKeychainTests.defaultTestSuite
suite.run()
guard let result = suite.testRun, result.executionCount == 14, result.totalFailureCount == 0 else {
    exit(1)
}
