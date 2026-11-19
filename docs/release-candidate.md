# MuscleDesk — first Play release candidate

## Blocking owner-decision update — 29 October 2026

The policy is not finalizable as a functioning release policy yet: Raj declines
personal manual request handling, and current deletion intake does not dispatch
an automated fulfillment workflow. The earlier reviewer assignment is withdrawn.
Atlas is now owner-confirmed and consistent with local configuration; Cloudinary
and Gmail remain confirmed integrations. Provider settings/retention remain open.
Follow [the scoped deletion plan](account-deletion-automation-plan.md) for the
smallest practical options and three remaining owner decisions. No automated
service, new reviewer, policy approval or deployment is implied.

## Current status — 29 October 2026

The [current release audit](release-audit-2026-10-29.md) supersedes historical
availability/configuration/test results below. The live privacy page now returns
200 but is an **unapproved draft**; the updated MuscleDesk deletion page returns
200 and protected deletion status returns 401. Neither receipt submission nor
hosted recovery/fulfillment was exercised. Local recovery/Gmail delivery already
passed the controlled rehearsal. Publisher/support/URLs and private signing are
configured; the immediate AAB gate is the live draft, not empty public fields.
Fresh validation: 1,674 Flutter tests, 884 backend tests, 17 release-tool tests,
Flutter analysis, formatting and backend lint passed. Offline signing report
loaded the upload key. No AAB, deployment, push or production write occurred.
The sections below preserve earlier audit history; follow the current report
for remaining approvals, build command and physical-device checklist.

Audit and local preparation: **27 October 2026**. Not approved for publication.
No production deployment, production record mutation, upload or Git commit was
performed. Existing modified/untracked work was retained.

## Current decisions and configuration

- Owner-approved Play ID: `com.semgroup.gymmanagement`. The owner must still
  confirm availability/history in Play Console; local inspection cannot prove it.
- Release name/version: **MuscleDesk**, `1.0.0+1`. Confirm versionCode 1 has not
  previously been uploaded for that ID. Debug keeps its existing package ID,
  `com.example.gym_management_app`, and `MuscleDesk · Dev` label.
- Android namespace/activity source remain `com.example.gym_management_app`.
  Changing namespace is unnecessary for a different release application ID.
- Production API: `https://gym-api.semgroup.in/api/v1/`. Dart, Gradle and the
  release helper reject development/staging release settings or another API.
- Current local public configuration: ignored `release/production.json`, with
  confirmed publisher/operator **Raj**, support email **pcterajbca7772@gmail.com**
  and intended policy URL `https://gym-api.semgroup.in/privacy-policy`. This
  updates the earlier empty fields; it does not approve policy publication.
- Approved deletion URL: `https://gym-api.semgroup.in/account-deletion`.
  Existing public-link UI reuses this default; release metadata still requires
  complete public information.
- Private upload key: `~/.muscledesk/signing/muscledesk-upload.jks`, RSA-3072,
  alias `muscledesk-upload`; file mode 600, directory 700. Ignored
  `android/key.properties` is mode 600. Random passwords were never printed.
  Gradle's release signing report successfully loaded this key. Back it and its
  signing properties up securely before any upload; do not regenerate it.

## Feature audit and verification boundary

| Area | Existing implementation / evidence | Remaining verification |
| --- | --- | --- |
| Login, signup, session, logout | Riverpod session authority, typed failures, scoped secure refresh storage, serialized rotation/logout, auth-aware GoRouter; auth/repository/interceptor/widget tests | Synthetic end-to-end signup/login/logout and process-death tests on the final Play-delivered release. The existing production session was not logged out for testing |
| Secure transport / logging | HTTPS release guards; protected client origin/path checks and redirects disabled; backup rules exclude credential preferences; diagnostics accept bounded enums/status/request IDs, not tokens or bodies | Review actual hosting logs/retention separately; no full penetration-test claim |
| Members and photos | Existing repositories, scoped registration ledger/photo outbox, authenticated image delivery and fallbacks; member/onboarding/photo tests | Isolated create/edit/photo interruption and registration handoff tests on release, without real customer records |
| Plans / memberships | Existing plan/purchase/renewal/cancellation routes, lifecycle/eligibility helpers and gym-timezone policy; membership/renewal/timezone tests | Synthetic expiry/renewal/cancellation across timezone/DST and interrupted writes on release |
| Payments / dues / revenue | Integer-paise models, existing Idempotency-Key, scope guards, pending-payment/renewal recovery and uncertain-outcome handling retained; financial tests | Authorized isolated full/partial/duplicate/interrupted-payment tests; no real payment was created |
| Dashboard / navigation / trainers / owner profile | Existing API-backed repositories, Riverpod providers, guarded routes, typed loading/error/empty states; dashboard/trainer/profile/router tests | Full final-release visual/accessibility and API smoke tests; owner/admin is the implemented product, not complete trainer/member self-service |
| Offline / expired session / server errors | Retryable startup preserves saved credentials for transient failures; invalid sessions clear credentials; repository failures and explicit recovery states | Final release airplane-mode/restart/expiry/server-failure exercises. This app is not a general offline-sync product |
| Account deletion | Local modules and mobile GET/POST envelope/receipt/scope behavior inspected; hosted route now authenticates; public form loads | No request submitted. Verify a synthetic receipt in an isolated account and establish actual manual fulfillment; intake is not deletion completion |
| Password recovery | No forgot/reset-password endpoint or reset delivery/token contract found in local backend auth routes/services or Flutter | Blocking requested feature: obtain the supported deployed contract/delivery configuration before client implementation. Do not invent endpoints or reset passwords using email alone |

Attendance and branch management remain retired. No member, membership, payment,
trainer, registration, photo, gym isolation or authentication safeguard was removed.

## Safe hosted checks

TLS-verified, unauthenticated GET requests only:

| Path | Actual result |
| --- | --- |
| `/api/v1/health` | 200; success |
| `/ready` | 200; success |
| `/api/v1/auth/account-deletion-request` | 401; `INVALID_AUTHENTICATION`, no-store; previously unavailable route now authenticates |
| `/account-deletion/` | 200 HTML; password/acknowledgement request form, no-store; still branded **Gym Management** |

The external page must reference MuscleDesk or the final listed developer before
submission. The continuation prepared that branding correction in local backend
source/tests and verified the page in an isolated GET-only browser preview.
The hosted page still has the old branding; deployment remains a separately
approved task. No VPS change was made. These responses do not prove every local
backend module is deployed or prove any production write flow.

On the connected, authorized vivo I2219 (existing debug APK), read-only navigation
through More → Request account deletion displayed **Verify your request**, with
the submit action disabled and no API-unavailable error. No password was entered,
acknowledgement selected or request submitted. The redacted screenshot was
inspected. Its public-page-not-configured message belongs to that older installed
APK; the new default URL is covered by a configuration test and the fresh debug
build, which was not installed during this mission. This is not release-build QA.

## Automated validation and build

- `dart format --output=none --set-exit-if-changed lib test`: 235 files, 0 changes.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter json`: **1,658 passed, 0 failed, 0 skipped**.
  The first run had one old fixture expecting a development release; it was
  updated to the new production-only policy, retaining protected-route assertions.
- `python3 -m unittest discover -s tool -p 'test_*.py' -v`: **8 passed**.
- `cd android && ./gradlew :app:signingReport --offline --console=plain`:
  release key loaded successfully; no credentials printed.
- `flutter build apk --debug --no-pub --dart-define-from-file=release/production.json`:
  passed. This debug build was not installed over the user's existing app.
- `python3 tool/play_release.py --config release/production.json`: exit 2,
  intentionally blocked on the three empty public fields.
- `flutter build appbundle --release --no-pub --dart-define-from-file=release/production.json`:
  failed at the Gradle guard: **Release requires final publisher/support
  information and public privacy/deletion URLs.** No AAB was produced.

No signed-release artifact, Play-delivered install, 16 KB runtime compatibility,
or Google Play approval is claimed. Android uses AGP 8.11.1 and the installed
Flutter SDK targets API 36; final AAB manifest, signing, ABIs and native alignment
must still be verified on the actual release artifact.

## Submission checklist — complete in this order

1. Confirm package availability/ownership, developer account verification/type,
   publisher name, public support email and app review access in Play Console.
2. Review the prepared [privacy-policy draft](privacy-policy-draft.md) and
   [evidence/confirmation/publication handoff](privacy-policy-review.md), approve
   the real operator/contact and operational decisions, confirm hosting authority,
   then publish an accessible HTML privacy policy describing actual account, gym,
   member/trainer, membership/payment, optional photo, recovery and provider data;
   supply its URL. Complete the three local empty public fields.
3. Arrange a separately approved deployment of the local deletion-page branding
   correction; establish a responsible manual-review/support
   process, response timeline, retention decisions and shared-gym ownership
   handling. Test intake/confirmation and fulfillment with isolated synthetic
   data. Do not automatically delete financial/audit records.
4. Provide a documented secure password-recovery backend/delivery contract and
   test it with isolated accounts. Do not use production password resets as probes.
5. Back up the upload key/passwords with restricted encrypted access. Enable Play
   App Signing and keep upload signing separate from the Play app-signing key.
6. Run `python3 tool/play_release.py --config release/production.json --check-urls --ca-file /etc/ssl/cert.pem --build`. Inspect signature, release package/name,
   version, API, permissions, all ABIs and 16 KB native alignment. Run a 16 KB
   emulator/device test and the release install/update/recovery scenarios.
7. Review the prepared [store-listing text](play-store-listing-draft.md), then
   complete the listing: MuscleDesk name, short/full descriptions, gym-owner/admin
   feature claims, real app icon, feature graphic, phone screenshots using only
   synthetic data, and accurate support/privacy/deletion links. No online payment
   gateway, attendance, reminders or unimplemented roles should be advertised.
8. Complete Data safety from `play-data-safety.md` plus actual vendor/hosting
   behavior; content rating, target audience, ads declaration, reviewer access
   and applicable health/fitness declarations. Do not claim no data collection.
9. With explicit owner approval, upload to internal testing, run pre-launch
   reports and test Play-delivered releases across supported Android versions.
   New personal accounts may require at least 12 opted-in closed testers for 14
   continuous days before applying for production access.
10. Resolve failed QA/security/operational gates, including backup restoration,
    monitoring and deletion fulfillment, before requesting public publication.

Official references (recheck in Play Console at submission):
[target API](https://support.google.com/googleplay/android-developer/answer/11926878),
[account deletion](https://support.google.com/googleplay/android-developer/answer/13327111),
[Data safety / privacy](https://support.google.com/googleplay/android-developer/answer/10144311),
[16 KB support](https://developer.android.com/guide/practices/page-sizes),
[testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465).

## Continuation — remaining local code and contract work

- Read the current dirty files and preserved all pre-existing work. No Dart app
  screen, authentication, dependency, API configuration or business rule changed.
- Fixed only the public deletion title/heading in local backend
  `src/modules/accountDeletion/routes.js` and added assertions in
  `tests/integration/accountDeletion.test.js`. The existing Iron Signal colors,
  typography, spacing, form fields, status codes and request-intake behavior are
  unchanged. Local browser verification showed the corrected title/form; no form
  was submitted. The production page was checked with GET only and still uses
  the old name. No local or remote fulfillment was performed.
- Documented [the exact existing account-access contract](account-access-contract.md),
  including why initial provisioning/member activation cannot implement recovery.
  Added concrete manual-review gates to [the operations runbook](production-operations.md).
  Password reset/delivery and approved fulfillment are still external requirements.
- Reproduced and fixed a release-verifier gap: normal JDK verification accepted
  an unsigned appended file. The helper now requires a verified signature, strict
  unsigned-entry checks and unambiguous ZIP entries, retaining support for the
  existing self-signed upload key. Real temporary JDK fixtures verified valid
  signing and rejection of unsigned additions; they were not application bundles.
- Rechecked public configuration: Play ID `com.semgroup.gymmanagement`, API and
  name match the approved values. Debug remains `com.example.gym_management_app`;
  namespace/activity remain unchanged. In Console, confirm package ownership and
  history, prior version codes and any required existing signing/upload
  certificate. If the package is already used by another app, stop rather than
  replacing its identity/key. Local files cannot certify availability.
- Keystore/properties remain private, ignored/untracked where applicable, mode
  600; no key was generated, replaced or exposed during the continuation.

Current continuation checks: Flutter analysis passed; Dart format checked 235
files with 0 changes; full Flutter suite **1,658 passed, 0 failed/skipped**;
release-helper tests **13 passed**; backend auth/deletion integration tests
**49 passed** against owned temporary MongoDB; backend lint passed without fixes.
The unchanged debug build was not repeated. Release preflight still returns exit
2 for the three missing public fields, so the already-demonstrated guarded AAB
failure was not repeated or bypassed. No signed AAB exists.

When the owner supplies final publisher name, public support email and published
privacy URL, complete only those public fields and run the documented guarded
build. Expected output after a successful signed build:
`build/app/outputs/bundle/release/app-release.aab`. Verify the actual artifact and
report its checksum/certificate/package/version before any separately authorized
upload. Public-launch gates above remain independent of build success.

## Privacy-policy preparation

The complete code-derived policy draft and a self-contained HTML export now
exist under `docs/privacy-policy-draft.md` and `docs/privacy-policy/index.html`.
The draft explicitly covers other people's gym records, optional contact/DOB and
emergency-contact details, fees/history/notes, photo processing and local raw-copy
limits, authentication/recovery, operational logs, providers and manual deletion.
It does not invent a publisher/contact, fixed retention, no-sale commitment,
audience policy, processing country, blanket encryption or completed deletion.

`docs/privacy-policy-review.md` records sources and the remaining decisions.
Public checks found an HTTPS root website at `semgroup.in`, but ownership,
publishing access and its privacy practices were not verified. The API's
`/privacy` and `/privacy-policy` paths return 404. The connected Sites inventory
contains no existing sites. No public policy destination is selected; no route,
DNS, VPS, backend, app configuration or hosted site was changed. The release
configuration retains its empty privacy URL and the existing guards stay active.

Publication still requires the final operator/publisher and monitored contact,
approved retention/deletion/audience/provider practices and an authorized hosting
destination. After approving and publishing the final HTML, verify its actual
public HTTPS URL and put that value into release metadata. A prepared local draft
does not satisfy the published-policy gate or make the AAB buildable by itself.

### Owner-supplied draft assumptions

The owner has now selected **India only** for the initial launch and stated that
the service does not intentionally target minors. Under-18 gym-member records
may nevertheless be entered; age eligibility, guardian arrangements and product
controls still need a decision before publication. Do not market the current
implementation as having age/consent verification that it does not implement.

The policy now uses the owner-supplied general retention principle (service need
and applicable legal obligations), while keeping actual category periods/criteria
and deletion fulfillment unresolved. Data uses are gym operations and necessary
hosting/photo-provider processing; no blanket no-other-sharing claim is made.
The existing manual deletion-request URL remains unchanged. No additional launch
country, India-only data residency, immediate deletion or legal guarantee is assumed.

At the earlier draft stage the owner had no approved policy website/domain. The
subsequent confirmed intended API-domain URL supersedes that selection blocker
for local preparation only, as recorded below. Publication/deployment is still
not approved; the observed root website remains unrelated to that authorization.

Before upload, select India as the initial distribution scope in Play Console,
complete the actual target-audience/content declarations and resolve the minors'
records question. No Play Console setting was changed. The three build inputs
still missing are publisher name, public support email and the **published,
approved** privacy URL; additional policy/operational decisions remain publication
gates. Other completed signing/configuration work is retained without regeneration.

Store name/short/full-description copy is now prepared separately in
`docs/play-store-listing-draft.md`, using only implemented owner/admin features.
It remains unsubmitted; screenshots, feature graphic, category/audience answers,
reviewer access and final public contacts are not invented or marked complete.

### Confirmed identity and intended policy URL — current state

Raj and `pcterajbca7772@gmail.com` are now the confirmed operator/publisher and
support/privacy contact. The intended URL is
`https://gym-api.semgroup.in/privacy-policy`; the candidate Android ID remains
`com.semgroup.gymmanagement`. Local release JSON and its public reference file
now contain those exact values. Earlier entries about three empty fields describe
historical checks, not the current configuration.

A static, public, read-only local backend route is prepared at `/privacy-policy`.
It serves `src/modules/privacyPolicy/privacy-policy.html` through the new router
registered in `src/app.js`. It needs no account/database lookup, creates no
session and exposes no write endpoint. Its bundled draft matches the policy
export; no new service, dependency, API auth behavior or database schema was added.
The existing Iron Signal document styles are preserved.

**No deployment or publication is approved or performed.** The draft warning and
noindex remain. The confirmed contact and intended URL do not resolve minors'
eligibility/guardian arrangements, retention periods/criteria, reviewer/timing
and ownership handoff for deletion, lost-password support, provider locations,
additional sharing or final effective-date/text approval. The policy cannot yet
be certified as finalized or compliant from code alone.

Build versus publication gates now differ:

- JSON/Dart/Gradle public metadata shape checks no longer fail for missing values.
  Signing remains private and configured; no key is regenerated.
- The existing fully checked build command uses `--check-urls --build`. It stops
  if the intended policy URL is not reachable as public HTTPS HTML; local route
  preparation does not change that hosted response. Do not omit this check to
  call a release ready.
- Raw Flutter/Gradle compilation does not check policy approval, fulfillment,
  Console ownership or live URL content. A valid configuration alone is not a
  verified signed artifact or public-release approval.
- Final policy approval/publication, Play Console identity/signing/version checks,
  supported password recovery, actual deletion fulfillment and release QA remain
  pre-publication gates; they are not all enforced by a compiler.

Once publication is separately authorized and the final URL is verified:

```sh
cd /Users/semgroup/Desktop/FlutterProjects/gym_management_app
python3 tool/play_release.py --config release/production.json --check-urls --ca-file /etc/ssl/cert.pem --build
```

This runs analysis/tests, builds and verifies the signed AAB without uploading.
Expected output after success:
`build/app/outputs/bundle/release/app-release.aab`. No such success is claimed
while the URL-checked workflow is blocked.

Validation for this confirmed-details/local-route pass:

- Release-helper tests: 16 passed, including HTTP errors, explicit draft rejection
  and prevention of a build after failed URL checks.
- Flutter configuration/account-privacy tests: 45 passed.
- Backend privacy/foundation/auth/account-deletion tests: 69 passed; backend lint
  passed without fixes. Tests used local fixtures, not production data.
- Markdown/export digest, all 11 contents anchors and the identical bundled
  backend HTML validated. Local browser rendering was inspected in desktop dark
  mode; no new phone, mobile/light-mode, full Flutter suite or build check is
  claimed for this pass.
- Public metadata validation passed. The read-only hosted URL check returned
  HTTP 404 for PRIVACY_POLICY_URL and exited 2. No signed AAB was built.

Follow-up privacy decision/deployment-plan pass (27 October 2026):

- The unapproved draft and last observed hosted 404 remain blockers. No remote
  deployment, publication, AAB build or fresh hosted check was performed.
- The release helper now rejects `--build` without `--check-urls` before any
  network/build work. All 17 helper tests and all 6 database-free backend privacy
  tests pass; backend app/route syntax, public metadata and Flutter-repository
  diff checks pass. No Dart/native source changed, so previous Flutter
  analysis/suite/device results were not rerun or represented as fresh results.
- [The deployment plan](privacy-policy-deployment-plan.md) lists the six remaining
  operator decisions and approval-gated backup, validation, release, HTTPS check
  and rollback steps. Actual server paths/service/proxy/backup state must be
  inspected before any future execution. No keystore, signing properties,
  production configuration, backend source or database was changed in this pass.

Privacy evidence/decision follow-up (27 October 2026):

- Added [the decision checklist](privacy-release-decisions.md), separating Raj's
  approvals, provider/configuration verification and required release outcomes,
  with unapproved India-launch defaults and minimum recovery/fulfillment criteria.
- Added [the evidence register](privacy-policy-evidence.md): 45 statement groups,
  79 existing source-file references, bounded local-code evidence, operator-supplied
  facts and explicit unknowns. No assumption is promoted to a verified practice.
- Source-reference/document-link checks and policy/export consistency passed.
  Hash checks confirm the public draft, HTML, release guard/tests and entire
  deployment plan (including backup and rollback) are unchanged. All 17 helper
  tests and metadata preflight pass. No fresh Flutter/backend suites, device
  checks, production/provider inspection, hosted GET, deployment or AAB build
  were performed for this documentation-only pass.
- No reset endpoint, fulfillment worker/tool, age control, retention policy or
  service deadline was invented or implemented pending approval. A support email
  alone does not establish functional password recovery or completed deletion.

## Local functional release-blocker pass — 27 October 2026

Raj approved the five implementation directions and isolated recovery API;
selected Gmail sender `pcterajbca7772@gmail.com`; assigned Raj as deletion reviewer.
Backup reviewer, response/retention targets and actual category retention remain
unapproved. No privacy publication, deployment or production mutation approved.

Implemented locally:

- Adult owner-signup declaration and known-DOB under-18 member gates in creation,
  onboarding, profile changes, photo upload and member-account provisioning/
  activation. Server uses gym calendar/UTC fallback. Optional DOB is unknown age,
  not verified adulthood. No guardian workflow enabled; historical reads,
  committed receipts, photo removal and financial safeguards preserved.
- New [recovery request/complete contract](password-recovery-contract.md), Flutter
  route/UI/repository, hashed one-time proof with email/account binding and expiry,
  account/IP abuse controls, bounded generic acceptance, transactional replacement,
  credential-version/session revocation, safe failures and change notification.
  One pinned Nodemailer dependency provides Gmail TLS delivery. Private `.env`
  sender fields prepared, SMTP password blank; no real email sent.
- [Internal manual fulfillment](manual-deletion-workflow.md) with protected evidence
  references, scope revalidation, handoff/linked-record/pending-operation blockers,
  owner redaction/access revocation, unchanged business records and durable photo
  cleanup including abandoned assets. Completion waits for cleanup and operator
  evidence of outside-system/backup resolution and truthful notification. Default
  disabled; CLI rejects production and non-fixture databases. No public completion
  endpoint, automatic deletion or production-enabled operator procedure claimed.
- Draft/evidence/checklists updated to distinguish these local features from
  deployed/provider behavior. Draft/noindex and release guard remain intact.
  Existing backup/rollback steps preserved; deployment-plan addendum lists new
  imports/models/dependency so a partial `src/app.js` upload cannot silently omit
  required recovery files. No backend deployment performed.

Actual validation:

- Full backend `npm test`: **880 passed, 0 failed/skipped** on owned temporary
  MongoDB fixtures. Backend lint passed. No real provider email/photo writes.
- Full Flutter `flutter test --no-pub --reporter expanded`: **1,674 passed**.
  Final focused auth/recovery/age/onboarding-error tests: **96 passed**.
- Final `flutter analyze --no-pub`: **No issues found**. Initial analysis found a
  non-const constructor use and then a redundant test import; both corrected.
  Scoped Dart format check: 18 files, 0 changes. Initial new widget-test finders
  were corrected; no failing test remains. No APK/AAB or phone installation/QA.
- Release-helper tests: **17 passed**. Post-export privacy-route tests: **6 passed**.
  Draft Markdown/export/backend bytes and digest, all 11 anchors and 87 evidence
  source paths validated. The initial HTML validator's inline-whitespace handling
  was corrected; no source policy text was missing.

Read-only live evidence:

- Trusted HTTPS GET health/readiness: 200/success. Privacy: 404. External deletion:
  200 HTML, still old branding. Unauthenticated deletion status: 401. These do not
  verify hosted recovery POST, deletion persistence or fulfillment; none submitted.
- One authenticated Cloudinary configuration GET succeeded, with no allowlisted
  boolean flags exposed. No asset listing/read/write; no region/retention/backup
  conclusion. Local credential presence is not production-provider parity.
- No authenticated Play Console integration available. Local candidate ID remains
  `com.semgroup.gymmanagement`, version `1.0.0+1`; availability/history, signing
  association and account-specific testing requirements need Console verification.
  Existing private upload key/signing configuration was not changed.

Next gates, in order: privately configure the selected mail credential and
authorize controlled isolated delivery verification; approve retention/targets,
backup reviewer/escalation and wider deletion/identity/ownership handling; verify
provider/database locations, logs/backups/restore and off-app sharing; approve the
final policy and separately authorize any complete backend/privacy deployment;
verify hosted parity/public HTTPS, then run guarded signed build and release QA.
The draft/404 still block the checked AAB path. An isolated implementation or
signed artifact cannot substitute for actual fulfillment/provider readiness.

## SMTP verification follow-up — 28 October 2026

Raj supplied `RECOVERY_SMTP_PASSWORD` privately and approved the controlled inbox.
Gmail TLS/auth verification passed without logging secrets; backend lint and
67 focused auth/recovery/foundation tests passed. Actual `startServer` ran on
loopback with an owned disposable MongoDB replica set and selected SMTP fields
only; it did not use the `.env` database URI. One synthetic account was created.
Two recovery messages and one change notice were accepted by Gmail SMTP; all
39 rehearsal checks passed, including an expired-fixture rejection, single use,
new-password login and both old access/refresh session revocations. The generated
proof had the real 900-second deadline; this was not a 15-minute elapsed wait.
Backend and temporary data were cleaned up; the private `.env` was unchanged.
See [the complete verification record](smtp-recovery-verification.md).

Raj confirmed receipt of all three test messages. No production/phone/AAB check,
deployment, public policy approval or publication is inferred from this test.
No application code, dependencies, signing material or production configuration
was changed in this verification pass. Previous remaining operational/provider/
Console gates persist; local SMTP configuration is no longer blank/unverified.
