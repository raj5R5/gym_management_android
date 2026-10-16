# Durable recovery native storage patch

These runtime sources are pinned copies of `flutter_secure_storage` **11.2.0**
and `flutter_secure_storage_darwin` **0.4.3** from the resolved pub.dev packages.
Their licenses are retained. Each `UPSTREAM_SHA256SUMS` records the original
copied files before patching, including the original pubspec. Root path overrides
make the native patch reproducible; do not patch the global pub cache.

Original hosted-package checksums from the pre-patch lockfile:

- flutter_secure_storage: `d4e1fb6b2cb524868929e78dc0282fa000554b22060fb53789dc481c9fc95bb8`
- flutter_secure_storage_darwin: `a031ceac9b070e62ef183cd7f7d1a8798ebde402d5049f0fe6eb3a51bd797a21`

Only runtime/native test sources, package metadata and licenses were copied.
The upstream `resolution: workspace` directives were removed to allow local path
dependencies. Package versions and existing platform requirements are unchanged:
Android minimum SDK 24, Java 17, iOS 13.0. No new runtime dependency is introduced.

## Patch boundary

`writeOnboarding`, `readOnboarding`, and `deleteOnboarding` are opt-in method-channel
operations. The scoped `OnboardingSecureStorage` adapter uses them for onboarding and payment recovery. Ordinary authentication
`write`, `read`, and `delete` methods retain upstream behavior. Darwin's ordinary
write fallback is intentionally unchanged for authentication; onboarding never
uses it. The new methods accept only `gym.onboarding.v1.` and `gym.payment.v1.` keys (the Dart adapter validates
every call). Unsupported Dart platforms fail closed instead of using an unverified
storage backend.

The existing `gym.onboarding.v1...pending` slot is used for both schema versions.
Existing onboarding keys, request bodies and v1/v2 ledgers remain unchanged.
Payment collection adds a separate `gym.payment.v1...pending` slot scoped by
environment, canonical API URL, actor, gym, member and subscription. It uses the
same verified native operations; ordinary authentication storage is unchanged. Android's existing preferences file, key prefix, wrapped
AES key, algorithm configuration and Keystore aliases are retained. Darwin keeps
the existing service/account and updates only `kSecValueData`, preserving the
actual item's accessibility and legacy access-control envelope.

## Android contract

The new native path uses the existing cipher. Before acknowledging a write it
uses checked `Editor.commit()` barriers for the current wrapped-key preferences,
namespaced and legacy algorithm configuration, then the encrypted record. Missing
wrapped-key metadata fails closed. Calls run through a process-wide background
operation queue; there is no destructive reset/delete/rollback on persistence failure.

`commit()` returning false or throwing is ambiguous. API 24's
`SharedPreferencesImpl.writeToFile` can report `true` without writing an existing
file when the editor made no changes; re-putting identical cached values is NOT a
barrier. Onboarding therefore stages `clear()` and exact snapshot reinsertion in
ONE editor and checks ONE synchronous `commit()`. Android processes clear before
staged puts under its map lock. For a nonempty snapshot this forces `changesMade`
on API 24 (and a new memory generation on newer Android), so the synchronous
commit writes the whole required snapshot. It does not write a random marker or
commit an intermediate empty file. All unrelated values are reinserted unchanged.

Both writes and verification reads use this replacement barrier. Wrapped-key,
namespaced configuration and legacy configuration barriers finish before the
record barrier; any failure prevents record acknowledgement. Required wrapped-key
and effective cipher configuration contain nonempty entries. An empty unused
configuration has no encryption dependency to certify. An empty record snapshot
contains no result to expose or dispatch marker to authorize; saving/submitting a
record always requires a nonempty replacement barrier first.

A failed deletion of the last item is special: it may leave an empty cache but an
old disk record, and clearing/reinserting that empty cache cannot force a write.
The native helper retains an in-process ambiguity fence for that preferences
instance and rejects further reads/writes/deletes until process reconstruction
reloads disk. It does not add a persistence key, infer absence, or discard a saved
operation to unblock the user. The same fence covers a delete that persisted and
then threw. Startup must restore the actual disk record (or absence) after restart.

A later successful nonempty barrier can durably finish a previous failed write
without changing the JSON encoding, ledger revision, frozen body or key. If it
fails, dispatch/confirmation stay blocked. Dispatch still refuses a write-then-
throw marker even if a subsequent verification barrier succeeds, as before.

This guarantee is bounded by Android's documented synchronous `commit()` contract;
it does not promise protection from hardware/power-loss failures, uninstall,
data clearing, corrupt/unreadable preferences loading, or cross-process writes.
Every plugin instance/Flutter engine uses the SAME `StorageOperationQueue`. Queue
ownership spans a complete MethodRunner call: upgrade inspection, initialization,
wrapped-key creation/recovery, algorithm/migration configuration, and the requested
read/write/delete/barrier. It is released only at a terminal native result, NOT
when an asynchronous initialization or biometric call returns. Such continuations
can run on another thread while retaining exclusive operation ownership. Therefore
no second plugin operation can commit/apply a different editor between snapshot
capture and replacement, even if it uses another engine or key prefix. Normal auth
keeps its encryption, apply/read/delete behavior and result types; only scheduling
is coordinated. Android apply changes memory before returning, and the later
synchronous barrier flushes that map through the platform's disk-write ordering.

No Java monitor is held during storage work or while awaiting callbacks. The small
queue monitor protects scheduling only; terminal completion is idempotent and
reentrant submissions wait in FIFO order. Engine detachment cannot shut down the
process queue or release another operation. Already accepted calls keep their
application context and drain safely; calls received after detachment fail closed.
Results are still posted to the platform/main thread. An asynchronous native
operation that never completes blocks subsequent storage operations rather than
allowing overlapping writers. This deliberate availability trade-off also means a
biometric prompt in one engine blocks storage calls in others until it finishes.

This coordination covers all writers reached through this vendored plugin. Do not
write its preferences directly from other native code, invoke storage/cipher helpers
outside the operation queue concurrently, or share these files across processes.
Those writers would bypass the serialization contract. No cross-process/device
lock, multi-key database transaction, or guarantee of power-loss survival is claimed.

Inspected platform sources:

- [API 24 commitToMemory/writeToFile](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-7.0.0_r1/core/java/android/app/SharedPreferencesImpl.java)
- [Current Android implementation](https://android.googlesource.com/platform/frameworks/base/+/main/core/java/android/app/SharedPreferencesImpl.java)
- [Editor atomic clear/put and commit contract](https://developer.android.com/reference/android/content/SharedPreferences.Editor)

## Darwin contract

Onboarding looks up the exact service/account using existing current, legacy and
cross-accessibility queries. Lookup failures propagate; only `errSecItemNotFound`
across those queries means absence. Found items are updated using their persistent
reference, with no result-return keys in the update query. An update error never
triggers add or delete. Confirmed absence permits add. A duplicate-item race gets
one further lookup/update attempt, without deletion or an unbounded loop.

Keychain calls finish before the Flutter result. Read-back uses Keychain rather
than a Dart value cache. Security errors remain ambiguous until verified by a
subsequent successful read; success does not imply protection against all device
storage failures. Explicit confirmed-operation acknowledgement is the only
onboarding delete path.

## Automated native validation

From `android/`:

```sh
./gradlew :flutter_secure_storage:testDebugUnitTest
```

Native unit suites: `OnboardingDurabilityTest` (18 tests) and
`OnboardingNativeBridgeTest` (12 API-24 Robolectric tests). Their injected preferences
model API 24's clear-before-put changesMade calculation, an existing disk file,
failed writes that leave cache changed, and unchanged commits that return true
without disk IO. Regressions first demonstrate that old false-success behavior,
then require the production replacement barrier to fail while storage is faulty.
They cover metadata ordering/initialization failures, confirmation/dispatch
blocking, identical writes, restart reconstruction, unrelated-value preservation,
and ambiguous empty deletions. The bridge invokes the real native method but uses
those preferences proxies and a synthetic cipher; its SDK annotation does NOT mean
it tests the real Android filesystem or Keystore.

`StorageOperationQueueTest` (12 JVM simulations) exercises production barriers with
authentication commit/apply, pending additions, updates/deletes, staged editors,
async key/config initialization, commit failures/exceptions, duplicate completion
and reentrant submission. `StoragePluginCoordinationTest` (9 API-24 Robolectric
tests) invokes actual MethodRunners on two plugin instances sharing preferences,
including an async continuation and detach/drain race. It verifies ordinary auth
still uses apply and cannot run during snapshot capture. A constructor test runs
the actual cipher factory and wrapped-key initialization and verifies shared-key
decryption; wrapping is injected, so this does not test Android Keystore hardware.

Real-framework tests use the SDK-only `OnboardingPlatformDurabilityTest` runner
(no additional test dependency). It runs 7 tests on API 24, including 5 fault
injection cases, and 2 disk/coordination smoke tests on other API levels. Compile:

```sh
cd android
./gradlew :flutter_secure_storage:assembleDebugAndroidTest
```

On an **API-24** emulator/device, install the generated
`build/flutter_secure_storage/outputs/apk/androidTest/debug/flutter_secure_storage-debug-androidTest.apk`
and run:

```sh
adb shell am instrument -w com.it_nomads.fluttersecurestorage.test/com.it_nomads.fluttersecurestorage.OnboardingPlatformDurabilityTest
```

These tests assert the actual `android.app.SharedPreferencesImpl` class. They inject
rename failure by redirecting its API-24 backup path into a nonexistent directory,
verify the real unchanged-editor shortcut, and require the fixed barrier to fail.
A fresh framework instance reloads XML from disk for restart-style assertions.
On other API levels the runner explicitly reports the API-24 fault cases as NOT
RUN and exercises only whole-map replacement/readback from the actual XML file.
The coordination smoke test uses the production queue/helper with real framework
preferences and verifies auth updates/deletion plus both pending values in XML.
It does not instantiate multiple live Flutter engines or kill/restart the process.
It uses no new runtime dependency or production storage namespace. Cold reconstruction is not a real
process-kill or hardware-failure test. These tests must actually run on API 24
before claiming that validation; merely building the test APK proves compilation.
The fresh initialization/process restart/decryption checks below remain separate.

On a Mac with full Xcode, from the Flutter project root:

```sh
bash vendor/flutter_secure_storage_darwin/native_tests/run.sh
```

This compiles the production Darwin storage manager/helper and executes 13 native
XCTest cases with injected Security API outcomes. It tests failed update/lookup/add,
duplicate races, valid update queries, legacy lookup and retained accessibility.
It runs on macOS, not an iOS device, and does not validate a live Keychain or power
loss. The test seam provides no delete capability to the replacement algorithm.

## Required platform integration checks

Run these in a development test harness using isolated test scopes. Do not use
production credentials or alter the application's registration UI for testing.

1. **Android fresh initialization and decryption:** start with no plugin metadata;
   save a v2 prepared record, persist a dispatch marker, terminate the process
   immediately after native acknowledgement, and reconstruct the adapter in a new
   process. Read/decrypt and compare the exact encoded record and frozen body/key.
   Repeat after reboot and on API 24 plus a recent Android device.
2. **Android failure injection:** instrument commits independently for wrapped key,
   configuration and record. Model false returns before persistence and writes
   that persist then report failure. Assert no network dispatch on marker failure;
   failed read barriers cannot return a confirmed result. Restart and recover the
   disk state. Ordinary force-stop loops alone cannot deterministically exercise
   filesystem failures or prove power-loss durability.
3. **iOS real Keychain replacement:** seed a scoped record with the existing
   service, non-synchronizable state and `unlocked_this_device` accessibility.
   Replace it, terminate/relaunch, and compare the recovered bytes and persistent
   reference. Exercise locked/protected-data-unavailable errors on a physical
   device: the original record must remain readable after unlocking. Deterministic
   update failure tests must verify zero `SecItemDelete` calls.
4. **iOS legacy compatibility:** seed both the old empty-flags access-control
   envelope and an older accessibility level; replace through the new method and
   verify the same persistent reference, service/account and accessibility remain.
   Test a duplicate-item creator race and entitlement/lookup failures.
5. **Both platforms:** seed an indented v1 record with microsecond timestamps and
   its original key. Restore without migration; retry with the same frozen request
   and idempotency key. Repeat for an unresolved v2 ledger and a confirmed result
   (which must not POST again). Include a dropped backend response after commit.
6. **Android overlapping Flutter engines:** run auth updates/deletes and onboarding
   barriers from two real engines; pause an async initialization/prompt, detach its
   engine, and attach another. Verify accepted work drains without overlapping
   preference mutations or losing another scope's record. Repeat on API 24 and a
   recent Android device, then kill/relaunch and decrypt the persisted records.

These device/integration checks are separate from Dart mocks and native fault-
injection unit tests. They remain required before claiming device-level durability.

## Maintaining the patch

On upgrade, compare the source against `UPSTREAM_SHA256SUMS`, reapply only the
opt-in native methods/helpers, verify key/metadata locations and legacy Keychain
queries, and rerun Dart, native and platform integration checks. Do not remove the
patch merely because a newer upstream version is available; inspect its actual
persistence semantics first.

## Payment recovery verification

Payment requests are frozen with their original key and millisecond timestamp,
saved before a verified dispatch marker, and replayed only via the existing
`POST gyms/:gymId/payments` idempotency contract. Confirmations remain durable
until Done/another-installment explicitly acknowledges them. Unknown outcomes
and conflicts cannot be unlocked by ordinary history or balance reads.

Repeat the device restart/reboot and protected-data tests above with a
`gym.payment.v1.` record, including full payment (zero remaining balance), a
committed response lost before confirmation, and actor/gym/API changes. Open
member membership details to review the saved payment even when dues are zero.
Dart restart simulations and native fault-injection tests do not prove real
device filesystem or Keychain durability. The underlying platform limitations
listed above still apply.
