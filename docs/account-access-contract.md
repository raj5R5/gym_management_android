# Account access, recovery and deletion — current contract

Inspected 27 October 2026 against the local backend source. This documents existing
behavior, not proposed endpoints. Hosted mutation behavior has not been tested.
Production API base: `https://gym-api.semgroup.in/api/v1/`.

## Historical baseline: no supported reset API existed before the approved implementation

**Historical inspection below is superseded for the current local candidate:**
Raj approved the [new recovery contract](password-recovery-contract.md). Request/
complete APIs, digest-only proofs, credential revisions/session revocation,
Gmail TLS delivery adapter and the Flutter recovery screen now exist locally.
SMTP password is blank; real mail and hosted recovery are unverified. No existing
endpoint was inferred from activation/provisioning. The original findings below
explain why those older routes cannot be reused as reset. They are not a claim
that the new candidate still lacks recovery source.

No forgot-password, reset-request, reset-token verification, password replacement
or reset-email delivery route/service was found in `src/`. There is no reset-token
model or mail-delivery integration in the inspected dependencies. The Flutter
client must not guess a path or report a reset email/success that was not confirmed.
If the deployed backend differs, obtain its exact reviewed contract first.

The following password-related APIs are **not account recovery**:

| Existing route | Exact purpose / boundary |
| --- | --- |
| `POST /api/v1/user-accounts/:userId/password` | Body `{password}`; one-time **initial** provisioning, 200 `{passwordProvisioned: true}`. Password 15–128 characters plus existing predictability validation; existing hash returns 409 `PASSWORD_ALREADY_SET`. Only the explicitly enabled development/test bootstrap listener, restricted to direct loopback. Absent from the main listener and forbidden in production. Never expose or proxy it to implement Forgot password |
| `POST /api/v1/account/activate` | Body `{token, password}`; 43-character base64url activation token and the same 15–128-character password policy; 200 `{activated: true}`. Consumes an unexpired unused member activation credential and requires an active account **without** a password hash. It cannot replace an existing owner's/member's password. Rate limit 20 per 15 minutes plus general limits |
| `POST /api/v1/auth/register-owner` | Body `{ownerFullName, email, password, gymName, gymContactPhone?}`; creates a new account/gym/admin grant transactionally. 201 `{accountCreated: true, gymCreated: true}`; does not return tokens or reset an existing account. Rate limit 5 per 15 minutes plus general limits |

Before implementing recovery, the backend owner must supply/approve identity
verification, delivery channel/provider, exact paths/methods/schemas/errors,
token expiry/single-use/rate limits, session revocation and mobile/public-web
handoff. These are unresolved requirements, not an invented API specification.
Email address alone is insufficient authority to replace a password. Users unable
to authenticate also need an approved support-assisted deletion/recovery process.

## Implemented mobile authentication

All success responses below use `{success: true, data, meta: {requestId}}`.
Failures use `{success: false, error: {code, message}, meta: {requestId}}`.
Passwords/credentials are never echoed in failures. Send JSON; the mobile client
sends no Origin or Cookie and disables redirects.

Minimum future recovery and deletion acceptance criteria are separated from this
existing contract in [the release decision checklist](privacy-release-decisions.md).
That checklist proposes security requirements, not new endpoints. The confirmed
support email alone is not a functioning reset or deletion-fulfillment mechanism.

| Method / path relative to API base | Request / auth | Success data |
| --- | --- | --- |
| `POST auth/login` | `{email, password, client: "mobile"}`. Email trimmed/validated, max 254; password preserved, 1–128. Rate limit 30 per IP per 15 minutes plus general limits | 200 `{user, gymAccess, accessToken, refreshToken, expiresIn, tokenType: "Bearer"}` |
| `POST auth/refresh` | `{refreshToken}`; rotating opaque 43-character base64url credential. Rate limit 60 per IP per minute plus general limits | 200 `{accessToken, refreshToken, expiresIn, tokenType: "Bearer"}`; no identity fields |
| `GET auth/me` | Bearer access token; active account/session required | 200 `{user, gymAccess}`; only active grants for active gyms |
| `POST auth/logout` | Flutter sends `{refreshToken}`. Backend also supports a verified Bearer token or both. At least one valid credential is required; this revokes session access, not account data | 200 `{loggedOut: true}` |

`user` contains `id`, `email`, optional `displayName`, `status`; grants contain
`id`, `gymId`, `role`, `status`. Credentials are infrastructure-only: refresh in
scoped platform secure storage, access in memory. Auth responses are no-store.
401 `INVALID_CREDENTIALS` is the generic login failure; 401
`INVALID_AUTHENTICATION` means invalid/expired session or credential; 400
`VALIDATION_ERROR`, 403 `CORS_ORIGIN_DENIED`, 429 `RATE_LIMITED` and sanitized
500 errors remain distinct. Web cookie transport has separate strict-origin
rules and is not a substitute mobile/reset transport.

## Implemented deletion request intake

| Method / path | Existing request and response |
| --- | --- |
| `GET /api/v1/auth/account-deletion-request` | Bearer auth, no body, empty query only. 200 envelope with `data: {request: null}` or the authenticated account's receipt |
| `POST /api/v1/auth/account-deletion-request` | Bearer auth, JSON **only** `{currentPassword, acknowledgement: "REQUEST_ACCOUNT_DELETION"}`. Current password 1–128; active account/hash reverified. 202 envelope with `data: {request: receipt}` |
| `GET /account-deletion` (outside `/api/v1`) | Public HTTPS HTML page; no app/login session required. CSS at `/account-deletion/style.css` |
| `POST /account-deletion` | URL-encoded form `{email, currentPassword, acknowledgement: "REQUEST_ACCOUNT_DELETION"}`, max body 4 KB. Password verification without creating a session. 202 HTML receipt; no submitted password/email echoed. Inactive accounts can use this path |

Receipt: `{id, userId, status, requestedAt}`. IDs are server-generated ObjectId
strings; `requestedAt` is a UTC ISO instant. Status is `requested`, `in_review`
or `completed`. The public client cannot choose user/gym ID, change status or
complete fulfillment. One unique account request and atomic upsert preserve the
same receipt and original request time across retries/concurrent submissions.

Both password-submission paths are limited to 5 per IP per 15 minutes, in addition
to general limits. All deletion responses are no-store. Wrong current password
in-app: 400 `ACCOUNT_DELETION_PASSWORD_INVALID`; unknown email/wrong password on
the public form: identical 401 `INVALID_CREDENTIALS` JSON error. Other failures
retain the existing 400 validation, 401 authentication, 429 rate-limit and safe
500 error envelope. Public failure responses currently use JSON, not a custom
HTML error screen; do not claim the form returns HTML for every status.

Intake does not delete/deactivate accounts, revoke sessions, alter gym grants or
modify memberships, payments, photos or audit history. Flutter requires a valid
account-scoped receipt before showing Request received, then rechecks GET after
uncertain submission. Manual fulfillment is **not implemented as an API/worker**.
Use the approval gates in [the operations runbook](production-operations.md).

The new [manual fulfillment workflow](manual-deletion-workflow.md) is internal,
disabled by default and rehearsed only on synthetic data. It adds no public
completion endpoint and does not change the intake request/receipt contract.

## Source evidence

Backend root: `~/Desktop/BackendProjects/gym_management_backend`:

- `src/app.js`: actual auth, owner-registration, activation, deletion and bootstrap mounts.
- `src/modules/auth/auth.routes.js`, `auth.validation.js`, `auth.controller.js`, `auth.service.js`.
- `src/modules/userAccounts/userAccount.routes.js`; `src/middleware/bootstrapOnly.js`.
- `src/modules/memberAccount/account.routes.js`, `account.validation.js`, `account.service.js`.
- `src/modules/ownerRegistration/registration.routes.js`, `registration.validation.js`, `registration.service.js`.
- `src/modules/accountDeletion/routes.js`, `service.js`, `model.js`.
- `src/middleware/validate.js`, `errorHandler.js`; `tests/integration/auth.test.js`, `accountDeletion.test.js`.

Flutter: `lib/features/auth/data/auth_api_service.dart`,
`lib/features/account_privacy/account_deletion_repository.dart`,
`account_deletion_page.dart` and their existing isolated tests.
