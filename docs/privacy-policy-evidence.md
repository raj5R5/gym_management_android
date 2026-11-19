# Privacy policy statement evidence register

## Superseding evidence — owner decisions, 29 October 2026

Atlas is now OWNER-confirmed; a private read of local configuration found SRV
and an Atlas hostname suffix without printing values or connecting. This supports
the local arrangement, not the live cluster, regions or backups. Cloudinary and
Gmail are CODE-confirmed in `photo.storage.js` and `recovery.delivery.js`.
Raj's no-personal-copies/no-planned-personal-exports/no-intended-sale declarations
are OWNER evidence. The earlier Raj reviewer assignment is withdrawn: no manual
handler is assigned and production intake has no fulfillment worker. The legacy
service/CLI requires human evidence and isolated execution. See
[precise inspection and proposed replacement](account-deletion-automation-plan.md).
Claims below about an assigned reviewer or unknown database-provider identity
are historical; provider retention/locations and production operation remain open.

## Latest evidence — 29 October 2026

Read-only HTTPS GETs confirmed the public privacy draft (200 HTML, exact pre-edit
local HTML match), updated MuscleDesk deletion page/email option (200), protected
deletion status (401), and health/readiness (200). This supersedes older 404,
old-branding and undeployed-page descriptions below; it does not establish the
VPS commit or full module/configuration parity. The three local policy copies
now accurately describe public availability and retain unapproved-draft warnings.
Controlled local Gmail delivery is verified in `smtp-recovery-verification.md`;
older blank-credential/no-real-mail statements are historical. Hosted delivery,
production fulfillment, provider locations/retention and backups remain open.
See [current release audit](release-audit-2026-10-29.md) for exact evidence and
fresh automated results. No privacy approval or production action is implied.

27 October 2026. Internal companion to [the unchanged draft](privacy-policy-draft.md)
and [decision checklist](privacy-release-decisions.md). Covers each substantive
statement/group in draft sections 1–11, including explicit unknowns and advice.
Checklist A1–A6 separates subsequently approved directions from remaining proposals. Local implementation and deployed/provider behavior are not interchangeable.

Evidence labels:

- **CODE:** Supported by inspected local implementation. Not proof of the deployed
  revision, effective configuration, full runtime behavior or all business uses.
- **OWNER:** Supplied by Raj in this chat. Not independently verified provider,
  Console, legal or operational evidence.
- **HISTORY:** Prior recorded read-only observation, not a fresh remote check.
- **OPEN:** Requires a decision, contract/configuration record, deployed check or
  implemented procedure. Must remain qualified/unapproved until resolved.
- **ADVICE:** Proposed guidance/boundary, not a claim that a mechanism exists.

Path roots: `F:` = `/Users/semgroup/Desktop/FlutterProjects/gym_management_app/`;
`B:` = `/Users/semgroup/Desktop/BackendProjects/gym_management_backend/`.
Paths below identify actual source files; model fields, methods and route names
locate the relevant evidence without exposing private configuration values.

## Section 1 — service, audience and identity

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E01 Gym/member/trainer/membership/fee administration; policy scope includes app, API and deletion page | B:src/app.js route mounts; B:src/modules/members/member.model.js; B:src/modules/trainers/trainer.model.js; B:src/modules/subscriptions/subscription.model.js; B:src/modules/payments/payment.model.js | CODE. Deployed parity is B1 in checklist |
| E02 India-first launch; Raj; supplied contact; intended URL; package candidate | Raj's confirmed instructions; F:release/production.example.json; F:lib/core/config/public_app_info.dart; F:android/app/build.gradle.kts | OWNER + CODE configuration. Console availability, jurisdiction and publication authority OPEN; not inferred from package/domain |
| E03 Gyms can hold records for people without logins and authorize staff | Optional `userId`, required `gymId` in member/trainer models; B:src/modules/gymAccess/gymAccess.model.js; B:src/modules/authorization/authorization.service.js | CODE. Actual staff conduct and allocation of gym/operator responsibilities OPEN. Contact-your-gym instruction is ADVICE, not proof of a rights process |

## Section 2 — data categories

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E04 Account email/name/status/password verification, gym contact/timezone, owner optional phone/photo and grants | B:src/modules/userAccounts/userAccount.model.js; B:src/modules/gyms/gym.model.js; B:src/modules/gymAccess/gymAccess.model.js; B:src/modules/ownerProfile/profile.model.js; B:src/modules/ownerRegistration/registration.validation.js | CODE field/validation definitions; does not mean every optional field is populated |
| E05 Member/trainer codes, names/phone/status, optional DOB/gender/address/emergency contact, specialization and linked assignments | B:src/modules/members/member.model.js; B:src/modules/trainers/trainer.model.js; B:src/modules/trainerAssignments/assignment.model.js | CODE. Emergency contact comes from submitted input, not phone-contact import. Existing customer records not inspected |
| E06 Plan descriptions/price/duration, dated memberships/renewal/cancellation, notes, payments/method/reference/actor and balances | B:src/modules/membershipPlans/plan.model.js; B:src/modules/subscriptions/subscription.model.js; B:src/modules/subscriptions/renewal_operation.model.js; B:src/modules/payments/payment.model.js; B:src/modules/gymDashboard/dashboard.service.js | CODE. Bookkeeping values can be personal/financial information |
| E07 Optional identifying photos, references/revisions and local recovery; no facial/biometric matching implemented | F:lib/features/members/photos/member_photo_models.dart; F:lib/features/members/photos/member_photo_service.dart; B:src/modules/memberPhotos/photo.image.js; B:src/modules/memberPhotos/photo.storage.js; B:src/modules/ownerProfile/profile.routes.js | CODE photo pipeline. Negative claim limited to inspected source/dependencies, not a guarantee about every provider use |
| E08 Password/session credentials, personal/financial recovery snapshots and new reset proofs | Existing auth/stores above; B:src/modules/passwordRecovery/recovery.model.js; B:src/modules/passwordRecovery/recovery.service.js; F:docs/password-recovery-contract.md | CODE local: reset records store code/email digests, credential revision, expiry/use time, not raw codes. SMTP message contains the code. Hosted reset/delivery is unverified |
| E09 Deletion intake receipt plus internal review/case metadata; password not stored in request | B:src/modules/accountDeletion/model.js; B:src/modules/accountDeletion/service.js; B:src/modules/accountDeletion/fulfillment.model.js; B:src/modules/accountDeletion/fulfillment.service.js; B:tests/integration/accountDeletionFulfillment.test.js | CODE local and synthetic tests. Reviewer/evidence references, retention criteria and cleanup/outcome state are protected internal data. No real request/production fulfillment tested |
| E10 Request/record identifiers, status/time, safe diagnostics/security events; network IP processing | B:src/middleware/requestLogger.js; B:src/config/logger.js; B:src/modules/auth/auth.service.js (`securityEvent`); B:src/modules/auth/auth.routes.js (`authLimiter`); B:src/app.js global rate limiter | CODE for app logs/IP-based limiting. Exact proxy/DB/provider logs, access and retention OPEN; do not claim IPs are never processed |
| E11 Free text contains user input; avoid unnecessary sensitive details; payment bookkeeping is not card/gateway transfer | Descriptions/notes/reference fields in E06; F:pubspec.yaml; B:package.json; registered routes B:src/app.js | CODE limited negative finding: no card/CVV/bank-login/payment-gateway integration found. Input warning is ADVICE; does not prevent users putting sensitive text in notes |
| E12 Attendance/branches retired; historical records may remain, not erased automatically | F:docs/scope-cleanup.md; historical-only `branchId` in member/trainer models; B:src/app.js current mounts | CODE cleanup scope + qualified possibility. Actual historical collections/records and retention OPEN; no live DB inspected |

## Section 3 — sources and purposes

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E13 User/gym inputs, chosen photos and service operations supply data; authentication, authorization, records, membership and fee operations use it | B:src/modules/ownerRegistration/registration.routes.js; B:src/modules/members/member.service.js; B:src/modules/auth/auth.service.js; B:src/modules/authorization/authorization.service.js; B:src/modules/payments/payment.service.js; photo sources E07 | CODE purposes demonstrated by functions. Does not approve unrelated uses |
| E14 Dues/revenue, duplicate safeguards and uncertain-operation recovery | B:src/modules/gymDashboard/dashboard.service.js; B:src/modules/payments/payment.service.js; B:src/modules/subscriptions/renewal_operation.model.js; B:src/modules/memberOnboardingComplete/operation.model.js; client stores E08 | CODE behavior/design, not a fresh financial end-to-end test or certification of all failure cases |
| E15 Diagnostics and deletion requests support operations/review | Logging E10; intake E09 | CODE intake/diagnostics. Actual human review is OPEN, not proven by a queue |
| E16 No medical-record/workout-sensor/Health Connect/HealthKit/location/contact-import/SMS/microphone/ad-ID/behavioral-analytics integration found | F:pubspec.yaml; F:pubspec.lock; F:android/app/src/main/AndroidManifest.xml; F:ios/Runner/Info.plist; B:package.json; source/route inventory B:src/app.js | CODE bounded absence finding. Do not generalize to provider/off-app behavior or assert Android/iOS runtime verification. Postal address fields are manual inputs in E05 |
| E17 Necessary gym/service-provider operations only, without ads/unrelated sharing | Raj approved this direction; E13/E07/E29; inspected source/dependencies | OWNER approved restriction + CODE inspected integrations. Actual provider/off-app practices still OPEN; not a blanket verified no-sharing claim |

## Section 4 — device storage and images

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E18 Refresh credential in secure storage; access in memory; scoped registration/financial recovery storage | F:lib/core/storage/credential_storage.dart (`SecureCredentialStorage`); F:lib/features/auth/data/auth_repository.dart; F:lib/features/members/data/onboarding_secure_storage.dart; payment/renewal stores E08 | CODE. Platform/library guarantees do not establish encryption for every file |
| E19 Unresolved operations survive logout/restart pending acknowledgment; scoped protections prevent unsafe replay | `acknowledge` and scope validation in stores E08; F:lib/features/auth/data/auth_repository.dart (`logout`, `_clear`) | CODE intended persistence. Actual process-death/restore behavior still needs release QA |
| E20 Staged photos/metadata in app-private support files, not credential store; disposal attempts and failure recovery | F:lib/features/members/photos/member_photo_store.dart (`FileMemberPhotoStore`); F:lib/features/members/photos/member_photo_service.dart (`_deletePreview`, pending operations) | CODE. Original/picker-cache metadata and OS backup behavior OPEN; do not promise all local files encrypted or all copies erased |
| E21 Optional user-initiated camera/picker, fallback if absent/failed, no background library scan | F:lib/features/members/photos/member_photo_service.dart (`NativeMemberPhotoPicker`); F:lib/features/members/photos/member_photo_widgets.dart; F:pubspec.yaml (`image_picker`) | CODE. Device/system permission behavior needs platform QA. Settings guidance is ADVICE |
| E22 Validation/resized JPEG, stripping original EXIF/profiles; backend receives original for processing | B:src/modules/memberPhotos/photo.image.js (`preparePhoto`: decode, rotate, resize, JPEG without metadata preservation); B:src/modules/memberPhotos/photo.routes.js; B:src/modules/ownerProfile/profile.routes.js multipart handlers | CODE. Output stripping does not mean originals/picker/provider caches never held metadata; deployed processing must match |
| E23 Authenticated Cloudinary upload, protected API image delivery/revision behavior, durable replacement/removal cleanup | B:src/modules/memberPhotos/photo.storage.js (`type: authenticated`, `upload`, `read`, `destroy`); B:src/modules/memberPhotos/photo.routes.js; B:src/modules/memberPhotos/photo.service.js (`cleanup`); B:src/modules/ownerProfile/profile.routes.js; F:lib/features/members/photos/member_photo_repository.dart; F:lib/features/members/photos/member_photo_widgets.dart | CODE. Live provider configuration and cleanup backlog OPEN; immediate erasure of all copies not promised |
| E24 Logout clears credential, not gym records/all recovery; uninstall is not account deletion; backups/caches separately reviewed | Auth repository/stores E18–E20; F:android/app/src/main/res/xml/credential_backup_rules.xml; F:android/app/src/main/res/xml/credential_data_extraction_rules.xml; E09 intake | CODE boundaries. Backup XML excludes named secure preferences, not every app file. OS/provider behavior OPEN |

## Section 5 — access, vendors and cookies

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E25 Authenticated gym/role/assignment access; operator administration and independent gym exports | B:src/modules/authorization/authorization.service.js; B:src/middleware/authenticate.js; B:src/modules/trainerAssignments/assignment.model.js | CODE authorization intent. Actual privileged operator/support access and gym exports OPEN; legal-role allocation needs A5/A6 |
| E26 Hostinger VPS identified as API host | Raj's hosting statement | OWNER only. Source has no proof of actual hosting account/region/agreements/logs; B2 verification required |
| E27 MongoDB stores service records; database hosting provider/location unverified | B:src/config/database.js; B:package.json (`mongoose`); model paths above | CODE for technology/storage. OPEN for actual server topology, Atlas status, locations/backups; never disclose connection string |
| E28 Cloudinary images; Gmail recovery email/code/notification; device/browser storage/picker/public links | E23; B:src/modules/passwordRecovery/recovery.delivery.js; B:src/modules/passwordRecovery/recovery.service.js; F:lib/core/platform/public_links.dart; E18/E21 | CODE + OWNER sender selection. Gmail credential is blank and tests inject synthetic delivery. Actual delivery/provider retention, locations and terms remain OPEN; no real provider request made |
| E29 No discovered ad/analytics SDK; provider/website practices still unknown | Declared/locked dependencies F:pubspec.yaml, F:pubspec.lock, B:package.json; local HTML B:src/modules/privacyPolicy/privacy-policy.html | CODE bounded absence. Complete off-app/provider inventory, terms and final host tracking OPEN |
| E30 Mobile bearer/body tokens, separate secure HttpOnly browser refresh cookie; public deletion form no session/analytics script | F:lib/features/auth/data/auth_api_service.dart (`_options`); B:src/modules/auth/auth.controller.js (`cookieOptions`, `sendTokens`); B:src/modules/accountDeletion/routes.js | CODE transports. Proxy/host-injected cookies/tracking OPEN; native flow is not browser-cookie login |

## Section 6 — security boundaries

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E31 HTTPS/Argon2id, refresh digests, scoped permissions, rotation/revocation and recovery credential revisions | Existing E18/E25/auth source; B:src/modules/passwordRecovery/recovery.service.js; B:src/modules/auth/auth.service.js; B:src/modules/auth/authSession.model.js; B:src/modules/userAccounts/userAccount.model.js; B:tests/integration/passwordRecovery.test.js | CODE + isolated tests. New revision check invalidates old-session/reset races; legacy missing revisions use zero. Not live TLS/configuration proof |
| E32 Application diagnostics omit sensitive bodies/credentials; internal identifiers may appear in security logs | B:src/config/logger.js; B:src/middleware/requestLogger.js; B:src/modules/auth/auth.service.js; F:lib/features/auth/data/auth_diagnostics.dart | CODE designed logging boundaries. Not evidence about VPS, database, reverse-proxy or provider logs |
| E33 No absolute security/end-to-end encryption/all-at-rest guarantee | Backend decodes photos and processes records E13/E22; local private-file boundary E20 | CODE prevents an end-to-end claim for these service functions. Server/database/backups/log encryption OPEN; absence of verification is not proof of no encryption |

## Section 7 — retention

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E34 Retain while needed for service/legal obligations; category schedule not approved | Raj's supplied principle; F:docs/production-operations.md; draft explicit retention confirmation | OWNER principle + OPEN schedule/enforcement. Not evidence that each retained record is required by law |
| E35 Expiry/cancellation/inactivation is not history erasure; finance/operation records preserve prior results | B:src/modules/subscriptions/subscription.model.js; B:src/modules/payments/payment.model.js; B:src/modules/memberOnboardingComplete/operation.model.js; E08/E12 | CODE historical storage. Not a general retention policy or proof every collection lacks other cleanup |
| E36 Credential/reset expiry and intended TTL cleanup differ from record retention; staged data/photo cleanup can persist | Existing session/activation sources; B:src/modules/passwordRecovery/recovery.model.js; B:src/modules/passwordRecovery/recovery.service.js; E19/E20/E23 | CODE expiry and TTL definitions; 15-minute reset default is a security parameter, not record-retention approval. Actual deployed indexes/worker execution OPEN |
| E37 No approved financial/log/backup/request/deletion schedule or turnaround | Draft confirmation; A2/A3 remain unapproved; no approved category policy in release documents | OPEN operational declaration. Checklist numerical defaults are proposals only and cannot be copied as facts |

## Section 8 — rights, requests and fulfillment

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E38 Implemented editing/photo controls; contact gym/operator for requests, subject to verification/circumstances | B:src/modules/members/member.service.js; B:src/modules/ownerProfile/profile.service.js; E21/E23; F:lib/features/account_privacy/privacy_support_page.dart | CODE controls/contact presentation; ADVICE request routing. Actual rights/verification/response operation OPEN, not a legal guarantee |
| E39 In-app More deletion, external form without app, existing-password checks | F:lib/app/navigation/foundation_screens.dart; F:lib/features/account_privacy/account_deletion_page.dart; F:lib/features/account_privacy/account_deletion_repository.dart; B:src/modules/accountDeletion/routes.js; B:src/modules/accountDeletion/service.js | CODE. HISTORY public page/status observations in F:docs/account-access-contract.md do not verify live submissions. Never send passwords to support |
| E40 Public receipt remains intake; new restricted internal owner fulfillment has isolated tests and no public completion API | B:src/modules/accountDeletion/fulfillment.service.js; B:src/scripts/accountDeletionReview.js; B:tests/integration/accountDeletionFulfillment.test.js; F:docs/manual-deletion-workflow.md | CODE + synthetic tests. Raj assigned; backup/targets/retention OPEN. Default-disabled service and isolated-only runner do not establish production operations. Sole owner/linked records/pending operations block; financial records preserved |
| E41 New local request/complete recovery APIs and Flutter flow; real delivery/deployment not verified | B:src/modules/passwordRecovery/recovery.routes.js; B:src/modules/passwordRecovery/recovery.service.js; B:src/modules/passwordRecovery/recovery.delivery.js; F:lib/features/auth/data/password_recovery_repository.dart; F:lib/features/auth/presentation/password_recovery_page.dart; F:docs/password-recovery-contract.md | CODE + isolated tests, newly approved API rather than invented existing endpoint. Gmail sender approved; private SMTP credential blank. Support address alone is not functional recovery; public hosted POST remains untested |

## Sections 9–11 — age, locations, changes, contact and draft state

| ID / draft statement | Evidence | Status / limit |
| --- | --- | --- |
| E42 Adult owner declaration, disabled guardian workflow and known-DOB minor gates; missing DOB still unknown | F:lib/features/auth/presentation/owner_signup_page.dart; F:lib/shared/validators/profile_validators.dart; B:src/modules/members/member.age.js; B:src/modules/members/member.service.js; B:src/modules/memberPhotos/photo.service.js; B:src/modules/memberAccount/account.service.js; B:tests/integration/memberAgePolicy.test.js | CODE + isolated tests. Backend uses gym calendar with UTC fallback. No independent age verification/guardian consent or universal age assurance. Historical reads/receipts/photo removal preserved; deployment OPEN |
| E43 Locations/transfers, jurisdiction/applicable rights need verification; India market is not India storage | Owner's India instruction; provider evidence E26–E29; draft explicit confirmation | OWNER market + OPEN actual locations/legal scope. No country-specific guarantee or legal-compliance claim supported |
| E44 Final date/text and material-change notification need approval | Unset effective date and explicit draft controls; A6 unapproved | OPEN. Future notification wording is ADVICE/proposal, not an implemented notification system |
| E45 Confirmed contact/intended URL; updated local draft unapproved, hosted privacy absent | Owner confirmation; F:docs/privacy-policy/index.html; B:src/modules/privacyPolicy/privacy.routes.js; B:src/modules/privacyPolicy/privacy-policy.html; F:tool/play_release.py; F:docs/release-candidate.md | OWNER + CODE + fresh read-only GET: privacy 404; health/readiness 200; deletion HTML 200 with old branding; unauthenticated deletion status 401. No write behavior, provider configuration, publication or production parity proven |

## Proposed defaults and minimum-process statements

Raj approved the five implementation directions recorded in the checklist. Their
local implementation is evidenced above; actual provider terms, schedules and
service targets still need confirmation. Numerical defaults (30-day logs/backups, 2-business-day acknowledgment,
30-calendar-day fulfillment) remain unapproved planning suggestions, not measured
practices or statutory periods. The approved isolated recovery implementation now
uses a configurable 15-minute default proof lifetime as a security setting; it
is not a privacy-record retention period. C1–C6 and the
minimum workflows specify acceptance criteria for future implementation; they
must not be described as completed features in the public policy.

Sources for recommendations, not evidence of current MuscleDesk behavior:

- [OWASP Forgot Password](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html): generic responses, rate limits, random expiring single-use recovery credentials, secure reset and session handling. OWASP does not select MuscleDesk's provider, exact endpoint or approved token lifetime.
- [Google Play User Data](https://support.google.com/googleplay/android-developer/answer/10144311): accurate disclosures and accessible privacy policy. Not evidence of legal compliance or business practices.
- [Google Play account deletion](https://support.google.com/googleplay/android-developer/answer/13327111): in-app/external request paths and associated-data deletion with justified disclosed retention; request intake alone does not demonstrate fulfillment. It does not require an automatic worker or specify a universal password-reset API.

One authenticated read-only Cloudinary account-configuration GET succeeded; its
response exposed none of the narrowly allowlisted boolean flags. No asset lookup
or provider write was made. This is authentication/API-access evidence, not proof
of storage region, retention, backups or contracts. No production VPS/database
configuration, customer/account records or provider contracts were accessed. Local evidence supports qualified statements
only. Revalidate the register when implementation, providers or policy text changes;
Keep draft/export/backend copies synchronized when updating factual local scope;
remove draft controls only after final text approval.
