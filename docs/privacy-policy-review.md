# MuscleDesk privacy draft — evidence and publication handoff

Prepared 27 October 2026. This is an internal review/handoff, not the public policy.
The complete policy is [privacy-policy-draft.md](privacy-policy-draft.md); its
self-contained, responsive HTML export is [privacy-policy/index.html](privacy-policy/index.html).
Both explicitly remain drafts. No publisher/contact/public privacy URL was invented.

Current confirmed details: publisher/operator **Raj**; support/privacy email
**pcterajbca7772@gmail.com**; intended policy URL
`https://gym-api.semgroup.in/privacy-policy`; Android ID candidate
`com.semgroup.gymmanagement`. These are operator-supplied values, not invented
placeholders. They do **not** approve the policy text, effective date, deployment
or publication. A local backend route and bundled draft are now prepared for that
path; the hosted endpoint is not claimed to serve the policy.

Use the concise [decision/verification/implementation checklist](privacy-release-decisions.md)
for the remaining work. The [statement evidence register](privacy-policy-evidence.md)
maps all draft sections to local source, operator instructions or explicit unknowns.
Proposed defaults are not approved policy or verified current practices.

## Current local implementation pass

Raj approved the five directions and the new isolated recovery contract. Local
known-DOB minor gates, adult owner declaration, Gmail adapter/recovery UI and
restricted internal fulfillment are implemented and covered by synthetic tests.
See [recovery contract](password-recovery-contract.md) and
[manual workflow](manual-deletion-workflow.md). Raj is the assigned reviewer;
backup/targets/retention remain open. The private SMTP credential is blank.
The older intake-only/no-reset statements below describe the pre-feature
inspection; the evidence register and updated draft record current local scope.
No actual provider behavior, recovery email or production deletion is verified.

Fresh read-only hosted checks: health/readiness 200, privacy 404, deletion page
200 with old branding and unauthenticated deletion status 401. No POST was made.
Local Cloudinary credential fields are present. One read-only Cloudinary SDK
configuration GET authenticated successfully; none of the narrowly allowlisted
boolean settings were returned. No assets were listed/fetched/changed. This did
not verify locations, contracts, backup/log retention or live asset delivery.
No production VPS configuration or database/customer data was accessed.
No authenticated Play Console integration is available to verify ID ownership.

## Owner-supplied basis for this revision

These instructions narrow the draft; they do not independently verify deployment
or establish that the corresponding legal/operational controls are implemented.

- **Initial market:** India only. Do not assume other launch countries or infer
  India-only data storage from this choice.
- **Minors:** Not intentionally targeted, but gyms may potentially enter under-18
  member records. Account eligibility and minors' data handling remain unresolved
  publication gates; there is no verified age gate/guardian-consent implementation.
- **Uses/sharing:** Gym-management operations and required hosting/photo-provider
  sharing. The inspected dependencies do not show an ad/analytics SDK, but that
  cannot prove no additional sharing or off-app business uses.
- **Retention:** While needed for service provision and applicable legal
  obligations; exact category periods/criteria and enforcement need confirmation.
  This does not justify retaining every record indefinitely.
- **Deletion:** The existing approved public request URL remains
  `https://gym-api.semgroup.in/account-deletion`. Manual review/fulfillment only;
  do not promise immediate, automatic or completed deletion upon intake.
- **Hosting:** The owner subsequently supplied the intended API-domain policy URL
  and authorized local page/route preparation only. No deployment or publication
  approval is given by that URL choice.

## Implementation evidence

Backend paths are relative to `~/Desktop/BackendProjects/gym_management_backend`.
The source was inspected; no production database, account records, private photo,
credential or `.env` value was read to write this policy. Actual deployment,
vendor agreements and business operations require the confirmations below.

| Data / handling | Source evidence | Boundary or confirmation |
| --- | --- | --- |
| Email/name/status, password hash, account identifiers | `src/modules/userAccounts/userAccount.model.js`; `src/modules/auth/password.js`, `auth.service.js` | Raj is the confirmed operator; jurisdiction and any additional required operator details need confirmation. Package/domain do not establish those details |
| Gym name/contact/timezone; scoped role grants | `src/modules/gyms/gym.model.js`; `src/modules/gymAccess/gymAccess.model.js`; `src/modules/authorization/authorization.service.js` | Gym staff may enter other people's records; operator/gym responsibilities need approval |
| Member names/code/phone, optional DOB/gender/address/emergency contact; trainer equivalents and specializations | `src/modules/members/member.model.js`; `src/modules/trainers/trainer.model.js`; Flutter member/trainer forms and models | Emergency contacts are third-party personal data. No verified age/parental-consent gate |
| Owner phone/photo and gym contact editing | `src/modules/ownerProfile/profile.model.js`, `profile.validation.js`; Flutter `lib/features/owner_profile/` | Optional photo; profile update fields differ from signup fields |
| Plan, membership, renewal, cancellation reason/notes and snapshots | `src/modules/membershipPlans/plan.model.js`; `src/modules/subscriptions/subscription.model.js`, `renewal_operation.model.js` | Business/financial history, not workout-sensor tracking; notes can contain additional sensitive content |
| Fee amount/method/reference/time/notes and actor, due/revenue aggregation | `src/modules/payments/payment.model.js`; financial repositories/providers in Flutter | No integrated gateway, card/CVV or bank-login collection found. Manual references are still financial data |
| Server confirmed registration/financial receipts, snapshots and request digests | `src/modules/memberOnboardingComplete/operation.model.js`; renewal/payment models/services | The inspected server operation models store confirmed results/digests, not whole raw request bodies; client recovery stores also hold frozen requests. Receipt copies still contain personal/financial data and belong in deletion review |
| Optional selected photo and operation metadata in private device files | Flutter `lib/features/members/photos/member_photo_store.dart`, `member_photo_service.dart`; owner photo handoff uses the existing photo machinery | Not every file is in encrypted secure storage. Do not promise raw originals are metadata-free or erased on logout |
| Backend re-encoded photo, Cloudinary authenticated asset and protected delivery | `src/modules/memberPhotos/photo.image.js`, `photo.storage.js`, `photo.routes.js`; `src/modules/ownerProfile/profile.routes.js` | In-memory upload processing; processed JPEG strips EXIF/profiles. Originals can pass through app/API before processing; provider/backup copies and cleanup retries differ |
| Refresh credential in platform secure storage; access token in memory | Flutter `lib/core/storage/credential_storage.dart`; `lib/features/auth/providers/auth_providers.dart`, `data/auth_repository.dart` | No end-to-end encryption claim; auth state does not expose raw credentials |
| Durable local registration/payment/renewal recovery | Flutter `lib/features/members/data/onboarding_secure_storage.dart`, `pending_onboarding_store.dart`; `lib/features/memberships/data/pending_payment_store.dart`, `pending_renewal_store.dart`; vendored secure-storage native code | Recovery records can survive logout/restart; confirmed explicit cleanup differs from blanket erasure |
| Session/refresh/activation records and expiry | `src/modules/auth/authSession.model.js`, `refreshToken.model.js`; `src/modules/memberAccount/activation.model.js` | Configurable lifetimes; TTL cleanup is asynchronous. Not a general financial/member retention policy |
| Deletion request with manual review only | `src/modules/accountDeletion/model.js`, `routes.js`, `service.js`; Flutter `lib/features/account_privacy/` | No automatic fulfillment. Missing lost-password support, reviewer/timeline and approved retention remain launch blockers |
| Bounded request/security diagnostics; transient network addresses for rate limiting | `src/config/logger.js`; `src/middleware/requestLogger.js`; `src/modules/auth/auth.service.js`; Flutter `auth_diagnostics.dart` | App logger omits raw bodies/addresses, but hosting/proxy/provider logs are not verified. Never claim no IP processing |
| Photo choice/camera access; no discovered ad/analytics/Health Connect/location/contact-import SDK | `pubspec.yaml`, `pubspec.lock`, Android manifests; `NativeMemberPhotoPicker` | This is the inspected app's implementation, not proof that the operator or website performs no other processing |
| Credential backup exclusions; staged photo files separately stored | Android `res/xml/credential_backup_rules.xml`, `credential_data_extraction_rules.xml`; photo store | Not a blanket “all app data excluded from backups” or “all stored data encrypted” claim |
| Retired attendance/branch history | `docs/scope-cleanup.md`; historical branch fields in member/trainer models | No production collection contents checked; historical data may remain and must be considered |

## Confirm before publication

1. **Identity/contact:** Raj and the public email are confirmed. Verify monitoring,
   inquiry handling, operator jurisdiction and any additional operator details
   needed for the actual India operations; do not invent a company or address.
2. **Audience:** India is the initial market. Decide account-holder eligibility,
   whether/how gyms may record under-18 members, guardian authorization and any
   product controls needed. Do not turn “not intentionally targeted” into a
   “no children's data” or compliance claim.
3. **Actual providers:** Confirm Hostinger's role (owner reported VPS hosting),
   the database hosting provider/topology, Cloudinary account/contract,
   provider/subprocessor locations, backups and cross-border arrangements.
   MongoDB technology alone is not evidence of MongoDB Atlas hosting.
4. **Other uses/disclosures:** Confirm any sale, advertising/marketing, research,
   external exports, independent gym practices, legal disclosures/business
   transfers, support tools and monitoring not evident in this code. Absence of
   an SDK cannot establish a blanket no-sale/no-sharing commitment.
5. **Retention:** Apply the owner-supplied service/legal-obligation principle and
   approve actual periods or justified criteria for accounts,
   member/trainer records, financial history, operation snapshots, logs,
   photos, local recovery, request/audit records and backups. Do not invent a
   fixed period or claim verified server/backup encryption.
6. **Rights/deletion:** Name reviewer and support-verification route, response
   timeline, ownership handoff, retention exceptions and actual controlled
   fulfillment process. Intake is not completed deletion. The new recovery API exists locally but real delivery/hosted behavior remains
   unverified; see [the contract](password-recovery-contract.md).
7. **Website:** Verify domain ownership/publishing authority and the final host's
   logging, cookies, analytics, locations and retention. The prepared HTML itself
   has no scripts, analytics, external fonts/images or submission form.
8. **Approval:** Review the factual draft for the actual operations/markets,
   approve the final wording and effective date, and remove the editorial
   confirmation notices only after resolving them. No legal-compliance or
   Google Play approval guarantee is made by this preparation.

## Hosting investigation — read-only

| Checked source | Verified result | What it does not prove |
| --- | --- | --- |
| Connected Sites inventory | No existing sites returned | Does not mean the owner has no website elsewhere |
| `https://semgroup.in/` | DNS resolves, verified HTTPS GET returns 200 HTML; no MuscleDesk/privacy-policy identification found in inspected response | Does not verify owner control, current host/CMS, permission to add a page or suitability of that site's privacy practices |
| `https://www.semgroup.in/` | DNS resolves, HTTPS 301 to the root site | Does not establish domain ownership |
| API `/privacy` and `/privacy-policy` | Both return 404 JSON | These are not policy URLs; no new API route was added or assumed |
| Project documentation/configuration | Existing API/deletion URLs; no approved privacy host, website deployment project or authenticated publishing setup identified | API/deletion service availability does not establish a privacy publishing path |

**Intended URL selected; publication not approved:**
`https://gym-api.semgroup.in/privacy-policy`. A local public GET route is now
registered outside authenticated/database-dependent handlers, serving only the
bundled draft HTML with no-store and the existing security middleware. It accepts
no write operation, reads no account data and creates no login session. The
document remains marked DRAFT/noindex. This is local preparation, not a live URL
verification or authority to deploy. The historical 404 observations above refer
to the hosted service; they are not the new local route's behavior.

## Prepared publication artifact and exact next steps

- `privacy-policy-draft.md`: complete code-derived policy text, with unresolved
  factual/policy decisions explicitly marked.
- `privacy-policy/index.html`: self-contained static HTML export. Its
  `source-sha256` metadata records the Markdown source digest. Update/regenerate
  both together after review. No canonical/public URL or publisher schema was
  fabricated. `noindex,nofollow` and the draft banner are intentional for review;
  remove the draft controls only when the text is approved.
- Publication requires only a normal public static HTML page; it does not
  require new Flutter dependencies, a second backend service, database access,
  a login, a PDF viewer or running the app.

The remaining operational declarations above must be resolved before finalizing
the policy. After explicit publication/deployment approval, the backend deployment
candidate must include `src/modules/privacyPolicy/privacy.routes.js`, its bundled
`privacy-policy.html` and the registration in `src/app.js`. Keep that asset in
sync with the approved Markdown/HTML export. Do not deploy the current draft;
finalize its warnings/noindex/effective date only after approval. Verify the
actual public route, TLS/security headers and proxy reachability under the
separately approved deployment workflow. No Apache/VPS change is authorized here.

After final approval and authorized publication, verify the actual URL returns
200 HTML over trusted HTTPS without login, geographic restriction or an editor
interface; check mobile reading, links and incognito access. Remove draft
notices and set the approved effective date as part of that finalization.
The confirmed intended URL is already recorded as `PRIVACY_POLICY_URL` in ignored
`release/production.json`, alongside Raj and the confirmed email. This is an
intended destination, not proof of publication. Use the existing release helper
with `--check-urls --build`; do not omit the URL check to turn a 404/draft
destination into a claimed ready release. A successful metadata preflight alone
does not approve the policy text or make its URL publicly available.
Nothing in this handoff authorizes app upload, policy publication or deployment.

The approval-gated [deployment plan](privacy-policy-deployment-plan.md) covers
backups, local validation, controlled release, public HTTPS verification and
rollback. No step has been executed. The release helper now refuses `--build`
unless `--check-urls` is also supplied; the final policy still needs manual review.

Google's primary policy requires a comprehensive public policy, privacy contact,
data-handling/retention/deletion disclosure and an accessible HTML page linked
from the app and Play Console: [User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311).
Review the final text and Data safety answers against the approved actual
operations, not merely this source inventory.

For India-specific review, use the actual applicable instruments and launch-date
commencement/applicability, not a generic compliance promise:
[Digital Personal Data Protection Act, 2023 — India Code](https://www.indiacode.nic.in/bitstream/123456789/22037/1/a2023-22.pdf)
and [DPDP Rules, 2025 — MeitY](https://www.meity.gov.in/documents/act-and-policies/digital-personal-data-protection-rules-2025-gDOxUjMtQWa?pageTitle=Digital-Personal-Data-Protection-Rules-2025).
The policy draft does not assert that a particular provision is already in force
for MuscleDesk or that the current implementation satisfies it.

## Preparation checks performed

- HTML text matches all Markdown policy text; source digest matches; 11 policy
  sections and all 11 contents anchors validate. The initial validator's inline
  whitespace comparison was corrected; no policy text was missing.
- No scripts, embedded images, external styles/fonts, iframe or submission form
  is present in the prepared page. Its only outbound link is the existing
  approved deletion page. Draft/noindex controls remain intact.
- Actual localhost browser rendering and a contents link were checked. The
  reviewed screenshot was desktop/dark mode; mobile, light-mode and assistive
  technology visual QA are not claimed. Styles include the existing Iron Signal
  light/dark tokens, wrapping and a narrow-screen layout.
- All 13 existing release-helper tests passed. Release preflight still rejects
  the missing publisher/support/privacy fields. No fresh Flutter suite or APK/AAB
  build was run for documentation/static-page-only changes; the prior application
  validation remains recorded in the release report.
- No policy upload, hosted site creation, DNS/server/backend modification,
  customer-data access, app upload or Git commit was performed.

Subsequent confirmed-details/local-route pass (27 October 2026): Raj, the confirmed
support email and intended policy URL are now configured. The preceding missing-
metadata result describes the earlier preparation stage. Current metadata
validation passes; the URL-checked workflow stops with HTTP 404, exit 2. Six new
local privacy-route tests plus existing foundation/auth/deletion tests passed
(69 total), as did backend lint, 45 focused Flutter tests and 16 release-helper
tests. The helper also rejects the explicit unapproved-draft marker even if a
privacy page returns HTTP 200. Local browser inspection confirmed the route
renders the draft; the HTML/source digest and bundled asset match. No deployment,
publication, fresh full Flutter suite, phone check or AAB build occurred in this
pass. Local backend source changes are limited to the static route, asset,
registration and focused tests; production is untouched.
