# MuscleDesk release audit — 29 October 2026

**Not ready for Google Play submission.** Local automated validation passes and
the upload key loads. The live privacy page is an explicitly unapproved draft;
the supported release helper stops before building. No release AAB was produced.
This report supersedes older deployment/delivery status statements, not their
historical test evidence. Nothing was deployed, emailed, submitted, committed,
pushed or uploaded during this audit. Production forms were not submitted.

## Observed production state

Unauthenticated TLS-verified GETs, without cookies or credentials:

| URL/path on `https://gym-api.semgroup.in` | Result | What this establishes |
| --- | --- | --- |
| `/privacy-policy` | 200, `text/html; charset=utf-8`, no-store, no Set-Cookie | Public MuscleDesk/Raj/contact document; explicitly draft/unapproved, no effective date, unresolved declarations |
| `/account-deletion` | 200, HTML, no-store, no Set-Cookie | Updated MuscleDesk page, password form, support email, prominent email option for locked-out users and draft-policy link |
| `/account-deletion/style.css` | 200, CSS | Referenced stylesheet reachable |
| `/api/v1/auth/account-deletion-request` | 401, `INVALID_AUTHENTICATION`, no-store | Protected status route responds; earlier 404 mismatch is not reproduced |
| `/api/v1/health`, `/ready` | 200, success true | Health/readiness at inspection time, not write-flow or backup proof |

The live privacy response matched the pre-edit local backend HTML byte-for-byte:
SHA-256 `b7967ddb7a83f9e33ab6eb0ba9669088d51224b86cfbfc470240b857ec99d5b6`.
The local backend was clean at commit `ae1d7d7` before this task. Matching HTML is
not proof of the VPS commit, complete backend parity or production configuration.
No SSH/VPS inspection was performed. A local HTML correction now differs from
that live snapshot; this audit did not publish it.

The draft has substantive data categories/purposes, optional photo/Cloudinary
processing, credentials/recovery, sharing, retention and deletion sections.
It explicitly identifies MuscleDesk, Raj and `pcterajbca7772@gmail.com`.
Its assertion that the updated deletion page was undeployed is now stale, as is
its assertion that the policy destination exists locally only. Those facts were
corrected in the three local policy copies while retaining all draft warnings.
Provider locations, category retention, backup/log treatment and actual human
fulfillment remain unverified, not invented or silently approved.

## Deletion and recovery boundary

Flutter uses `GET/POST auth/account-deletion-request` relative to the approved
API base, with authenticated gym-owner account scope and password confirmation
on submission. The response envelope and receipt fields match the local backend.
More → Request account deletion is retained. Privacy & support is also accessible
while signed out and opens public HTTPS pages through the Android browser intent,
without passing application credentials; copy-link fallback is available.
Source and widget/channel tests support this; a final release device/browser
round trip was not performed today.

The external deletion page is a user-facing resource, not merely an API URL.
Its branding, prominent form/email pathway and public accessibility meet the
observable web-resource criteria. This does **not** prove complete deletion
compliance: receipt persistence, mailbox monitoring, identity verification,
shared-gym handling, justified retention, provider cleanup, backup handling and
truthful completion still require operational acceptance. Ordinary email creates
no automatic backend reference. No production deletion request was submitted.

Existing recovery contract: `POST /api/v1/auth/password-recovery/request` with
`email` returns 202/accepted; `POST /api/v1/auth/password-recovery/complete` with
`token` and `newPassword` resets only after valid proof. Local code implements
digested expiring single-use proof, throttling, secure hashing and session
revocation. Controlled local Gmail delivery was already confirmed by the user;
see `smtp-recovery-verification.md`. No hosted recovery POST/email was attempted.
Production SMTP configuration and delivery/reset/revocation therefore remain
unverified. Do not infer them from a health check or from a GET to a POST-only route.

## Android/application inspection

| Item | Current verified configuration |
| --- | --- |
| Release application ID | `com.semgroup.gymmanagement` through ignored `release/production.json`; Console ownership/history unverified |
| Debug ID / namespace | `com.example.gym_management_app`; release application ID is independently selected by Gradle |
| Name / version | MuscleDesk / `1.0.0+1`; Console must confirm unused versionCode |
| SDK | Installed Flutter defaults: compile 36, target 36, min 24; NDK `28.2.13676358` |
| Transport | Production API exactly `https://gym-api.semgroup.in/api/v1/`; release environment/API guards; main manifest forbids cleartext |
| Credentials | Refresh credential in scoped platform secure storage; access token in memory; serialized restore/rotation/logout; backup exclusions |
| Permissions/SDKs | Main manifest requests INTERNET. No ads/analytics, SMS, contacts, location or broad photo-library permission declared there. Final release merged manifest still requires artifact verification |
| Photos | User-initiated picker/camera, authenticated backend delivery, optional fallback and existing upload/outbox safeguards |
| Branding | MuscleDesk resource label, adaptive/monochrome gym-plate icon and native launch resources exist; store artwork is separate |
| Logging | Bounded auth diagnostic enums/status/UUID request identifiers; no raw password/token/body logger found in inspected app code |
| Signing | Existing private upload keystore and all four signing properties present; Gradle release report loads non-debug upload alias; key/properties mode 600, properties ignored/untracked |

No new Flutter/backend application behavior was changed. Existing gym isolation,
auth, members, plans, renewals, cancellations, payment idempotency/recovery,
photos, dashboard and trainer/profile flows remain represented in the passing
suites. Automated coverage is not production end-to-end acceptance.

## Actual validation

| Command/check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test` | 239 files; 0 changes; exit 0 |
| `flutter analyze --no-pub` | No issues; exit 0 |
| `flutter test --no-pub --reporter json` | 1,674 passed; 0 failed/skipped; exit 0 |
| Backend `npm run lint` | Passed |
| Backend `npm test` | 884 passed; 0 failed/skipped; disposable local MongoDB, no real SMTP |
| Backend `node --test tests/integration/privacyPolicy.test.js` after HTML correction | 6 passed; no database or external requests |
| `python3 -m unittest discover -s tool -p 'test_*.py' -v` | 17 passed |
| Android `./gradlew :app:signingReport --offline --console=plain` | BUILD SUCCESSFUL; release upload key loads; not debug alias |
| Release helper with `--check-urls --ca-file /etc/ssl/cert.pem` | Exit 2: explicitly unapproved live privacy draft; build intentionally not attempted |
| `adb devices -l` | vivo I2219 authorized as `device`; no install, session reset or application write test |

Local SDK/cache/test outputs can change when checks run; unrelated project source
changes were preserved. No claim of a fresh release APK/AAB, screenshot review,
16 KB runtime test or final-release device verification is made.

## Remaining gates, in priority order

1. **Raj + provider evidence:** establish actual database/hosting/photo/mail
   locations and access/retention terms, photo cleanup, log/backup lifetimes and
   restore handling; confirm off-app uses. Approve category retention criteria,
   identity/ownership procedures, request targets/escalation, unknown-DOB and
   historical-record handling, final wording, change notification and effective
   date. Do not enable guardian workflows that are not implemented.
2. **Raj + release engineer:** approve and validate the final policy, then
   separately authorize its deployment. Preserve the backup/validation/rollback
   steps in `privacy-policy-deployment-plan.md`. Public draft accessibility does
   not confer approval. No unrequested production rollback/removal is performed.
3. **Operations + QA:** verify hosted recovery using an expressly authorized
   isolated account and delivery plan; verify deletion intake and complete the
   operational fulfillment workflow, including sole-owner/linked-record cases,
   provider cleanup and backups. The existing operator CLI remains isolated-test
   only and is not a production fulfillment tool.
4. **Raj / Play Console:** confirm package ownership, unused versionCode, account
   verification/type, Play App Signing association and secure upload-key backup.
   Complete reviewer access and applicable testing requirements.
5. **Release engineer:** after policy approval/publication, use the command below,
   verify artifact manifest/permissions/signature/ABIs/16 KB alignment, and execute
   device acceptance before separately approved upload/public release.

## Build command — only after the policy gate is genuinely resolved

From the Flutter project root:

```sh
python3 tool/play_release.py --config release/production.json --check-urls --ca-file /etc/ssl/cert.pem --build
python3 tool/play_release.py --verify-bundle build/app/outputs/bundle/release/app-release.aab
shasum -a 256 build/app/outputs/bundle/release/app-release.aab
```

Expected output location, **not produced by this task**:
`build/app/outputs/bundle/release/app-release.aab`.
Do not use a direct Flutter command to evade the public-policy check.
The helper verifies signatures and ELF alignment; inspect the actual release
manifest and generated APKs as well, then test 16 KB runtime compatibility.

## Physical-device acceptance checklist — isolated records only

- [ ] Install the signed release/Play-delivered build and confirm ID, label,
  version, SDKs, icon and launch screen. Its ID differs from the existing debug
  app; a debug-to-release install is not evidence of a release update/session migration.
- [ ] Sign up/login, kill/reopen, restore/refresh session, logout and expired-session
  behavior; network loss must not discard valid recoverable credentials.
- [ ] Open privacy/deletion links signed out and signed in; verify public browser
  access, back navigation and missing-browser/copy fallback.
- [ ] Create/edit/search synthetic members, duplicate names/codes, missing photos,
  optional photo replacement/removal/interruption and known-minor DOB rejection.
- [ ] Purchase/renew/cancel synthetic memberships across gym timezone boundaries;
  verify statuses, expiry and history.
- [ ] Record synthetic full/partial payments; exercise duplicate/interrupted
  requests and recovery; compare dues, history and dashboard totals.
- [ ] Verify authorized trainer/profile/navigation flows, empty/error/retry states,
  offline startup, large text, light/dark mode, back gestures and keyboard layouts.
- [ ] Verify isolated recovery expiry/replay/reset and old-session revocation;
  deletion receipt vs completion, manual fulfillment and retained-record explanation.
- [ ] Check crashes/ANRs and run Play pre-launch plus a 16 KB emulator/device test.

## Play submission checklist

- Privacy URL: public but **unapproved draft**, not suitable as the final policy.
- Deletion URL: updated public resource available; operational acceptance pending.
- Data safety: inventory exists in `play-data-safety.md`; provider/sharing/retention
  declarations require evidence. Do not select no-data-collected.
- Listing: short/full descriptions exist in `play-store-listing-draft.md`; final
  review, 512px store icon, synthetic phone screenshots and feature graphic pending.
- Content rating, ads declaration, target audience/India distribution, app access
  and applicable health-app declarations require accurate Console completion.
- Signing/version: locally configured; no signed AAB or Console ownership proof yet.
- New personal accounts created after 13 November 2023 may require 12 continuously
  opted-in closed testers for 14 days before applying for production access.

Official sources checked on 29 October 2026:
[target API 36](https://developer.android.com/google/play/requirements/target-sdk),
[account deletion](https://support.google.com/googleplay/android-developer/answer/13327111),
[personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465).
These checks do not guarantee Google Play approval.
