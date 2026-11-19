# Password recovery — approved isolated implementation contract

27 October 2026. Raj approved local implementation of these **new** endpoints
after their proposal. Gmail SMTP sender `pcterajbca7772@gmail.com` was selected;
private credentials will be filled locally by Raj. No existing reset API was
found, no production reset request/email is authorized, and deployment is separate.

All paths below are relative to `/api/v1/`, public JSON, no cookies/login required,
no-store. Normal `{success,data,meta:{requestId}}` / safe error envelopes apply.

| Method/path | Exact body | Success / boundaries |
| --- | --- | --- |
| POST `auth/password-recovery/request` | `{email}` only; trimmed valid email, max 254 | 202 `data:{accepted:true}` for both unknown and eligible addresses. Acceptance is queued processing, **not proof of delivery or account existence**. No code/token/identity is returned |
| POST `auth/password-recovery/complete` | `{token,newPassword}` only; token 43 base64url characters; password uses existing 15–128-character/blocklist rules | 200 `data:{passwordChanged:true}` only after transactional reset, one-time consumption and session revocation. Does not log in or change email/gym ownership |

Invalid/expired/used/changed-identity credentials share 401
`INVALID_RECOVERY_CREDENTIAL`; invalid input 400 `VALIDATION_ERROR`; throttled
attempts 429 `RATE_LIMITED`; missing delivery or saturated queue 503
`PASSWORD_RECOVERY_UNAVAILABLE`; transactional-storage failure 503
`PASSWORD_RECOVERY_STORAGE_UNAVAILABLE`. Never echo raw credentials/errors.

Implementation security parameters: random 32-byte code, digest-only database
storage, 15-minute default validity (configurable maximum 30 minutes), request
limits by IP and normalized-email digest, complete limits by IP, bounded local
delivery queue. These credential lifetimes are not personal-record retention
periods or approved service-response targets. All limiter/queue state is per
process; multi-instance operation needs shared/edge abuse controls.

Send a plain-text code for pasting into the app, avoiding a new hosted reset page
or invented deep-link contract. Gmail transport uses verified TLS on port 465,
no SMTP debug logs, no file/URL attachments, no user-selected redirect. Blank
private SMTP credential disables delivery/recovery with 503 for all addresses.
Tests inject a synthetic adapter and never send real mail. Gmail account/app-
password availability, delivery and provider terms/locations remain unverified.

Queued requests can be interrupted by process death; users may retry under the
same abuse controls. Delivery errors are safely logged and failed credentials
invalidated, without changing the public generic acceptance response. This is
not a durable email outbox and must not be described as guaranteed delivery.
Successful reset triggers a plain change notification; notification failure does
not falsely roll back an already committed password change.

Bind codes to account, registered-email digest and credential revision. An email
or password change invalidates old proofs. Increment credential revision on reset
and compare account/session revisions during authentication and refresh so an
old-password login racing reset cannot restore access. Preserve legacy sessions
at revision zero until a reset; do not silently invalidate all existing sessions.

Acceptance tests use an owned temporary MongoDB replica set and synthetic delivery:
generic responses; missing delivery; wrong/expired/replayed tokens; changed email;
transaction/concurrent reset behavior; old password/access/refresh rejection;
new login; no financial/grant changes; rate limits; safe errors and notification
failure. Real delivery and public-app verification remain release blockers until
separately authorized isolated verification is completed.

## Private setup remaining — no email authorized by this document

**28 October update:** Raj supplied the private credential and explicitly approved
the controlled test recipient. Configuration and real Gmail SMTP authentication
passed. The actual local backend/disposable-database recovery rehearsal passed,
including three SMTP-accepted test messages, expiry rejection, one-time use,
password reset and session revocation. Raj confirmed receipt of all three test
messages. See [the verification record](smtp-recovery-verification.md). The blank-
credential statements below describe the initial setup, not the current local
file. This does not authorize production sending or deployment.

Raj's local backend `.env` now has `RECOVERY_SMTP_USER` and `RECOVERY_EMAIL_FROM`
set to the confirmed address, and blank `RECOVERY_SMTP_PASSWORD`; `.env.example`
documents the names without a secret. Existing private values were preserved.
Do not put this credential in Flutter, release JSON, Git or chat. Google app
passwords require eligible 2-Step Verification; account eligibility has not been
verified. Use an app-specific credential if available, never the ordinary Gmail
password. If unavailable, agree OAuth/another approved delivery mechanism instead
of weakening account security. Google prefers OAuth where supported:
[Google app-password guidance](https://support.google.com/accounts/answer/185833).
After private configuration, separately authorize an email test to a controlled
isolated account. No SMTP verification/send was performed in this task.
