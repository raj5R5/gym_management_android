# Production operations and deletion fulfillment

Local code preparation does not deploy changes to the Hostinger VPS. Do not run destructive operations against the hosted database for validation. The existing HTTPS API remains authoritative for membership eligibility, expiry, money and permissions.

## VPS configuration

The backend now supports optional `API_BIND_HOST` and `TRUSTED_PROXIES` (exact IP addresses/CIDRs, never `true`, `*`, hostnames or `/0`). Defaults preserve existing binding and disabled proxy trust. For a verified same-host Nginx topology, privately bind Node to `127.0.0.1` and trust only the actual proxy source, e.g. `127.0.0.1/32,::1/128`; confirm firewall/listener rules before applying. Nginx must overwrite forwarding headers and must not expose bootstrap routes/port. Otherwise proxy IP rate limits can unintentionally group all gym owners together. Multi-instance deployment needs shared rate-limit storage or coordinated proxy limits; current in-process limits are not a distributed limiter.

Use `NODE_ENV=production`, bootstrap disabled, actual secret environment configuration, TLS, transactional MongoDB, authentication/authorization and existing unique indexes. Never put JWT/Cloudinary/database credentials in Flutter. Restart through the existing service manager only after approved deployment. New deletion indexes are created during normal startup before listening; no indexes are dropped.

## Account-deletion intake — implemented locally

- Authenticated `GET /api/v1/auth/account-deletion-request` returns `{request: null}` or the current user's receipt.
- Authenticated `POST` at that path accepts only `{currentPassword, acknowledgement: "REQUEST_ACCOUNT_DELETION"}` and returns HTTP 202 with a receipt. Current password is reverified. It takes no user/gym ID or requested status from the client.
- External `GET /account-deletion` serves a script-free HTML form. POST accepts email/current password/acknowledgement, verifies the existing hash and records the same account-scoped request without requiring the installed app or creating a session. Inactive accounts can request externally. Unknown account/wrong password share the same error; attempts are rate-limited. Passwords are never placed in URLs or stored in the request.
- Unique account index and atomic upsert make duplicates/concurrent retries return one receipt. Status reads are scoped and no-store. Request fields contain only account reference, status and timestamps. It does not alter memberships, financial records, photos, sessions, account status or gym access.
- The app rechecks status after an ambiguous POST. No success is shown without a server receipt; a received request never claims completed deletion. Old deployed APIs present an explicit unavailable/retry state.

## Mandatory fulfillment before public launch — not automated

Current local status: Raj is the confirmed reviewer; backup reviewer and targets
are unapproved. A restricted internal fulfillment service and isolated-only
operator runner now exist; see [the tested workflow](manual-deletion-workflow.md).
The earlier statements below about the absence of tooling describe the original
intake-only stage. No automatic worker, approved production-enabled tool or live
deletion operation has been added. Ownership/linked-record/pending-operation
blockers and off-app retention/backup evidence still need operational resolution.

New [password recovery](password-recovery-contract.md) is locally implemented with
Gmail SMTP configuration. The private credential is blank; no real email was sent.
This does not establish deployed recovery or a completed support procedure.

The request queue is an intake workflow. **Actual account/data deletion is not yet implemented as an automatic worker**, because final retention rules and handling of sole gym owners/shared business records have not been agreed. The app must not be declared production-ready merely because this queue exists.

Establish an accountable operator, turnaround deadline, monitoring/escalation and a secure support channel. Review pending `AccountDeletionRequest` records using privileged internal access; do not expose a public/admin list of other users' requests. Confirm identity, gym ownership handoff, legal retention basis and data scope. Never make deletion conditional on retaining a paid subscription or completing unrelated tasks.

The approved fulfillment procedure must cover account credentials/sessions and grants, owner profile/photo and durable Cloudinary cleanup, linked trainer/member records where appropriate, local outbox/cache behavior after sign-out/account revocation, audit/request records, backups and any lawfully retained financial records. Assess data about other people separately; do not blindly cascade-delete a gym's member/payment collections. Use existing photo cleanup machinery rather than direct untracked provider deletion. Retained data needs a documented purpose and period, not indefinite retention.

Revoke access as part of actual fulfillment, verify deletion/redaction and provider cleanup, communicate the result, and only then mark the request completed through a controlled internal procedure. No completion endpoint or “pretend deleted” account toggle is exposed by this implementation. Test the approved process end-to-end on synthetic data before launch.

### Manual-review gates and evidence

1. Raj is the assigned reviewer and the support email is confirmed. A backup,
   monitoring/escalation arrangement and response/fulfillment targets are not finalized;
   this document is not a published support or retention policy.
2. Review the request queue through existing privileged, read-only internal
   access. Record the receipt/reference, reviewer, review time and scope securely;
   do not export customer records, passwords, tokens or database credentials into
   tickets/chat. There is no public queue or fulfillment endpoint.
3. Verify the requester using the authenticated receipt or a separately approved
   support-verification procedure. If the password is lost, stop for that approved
   procedure: initial provisioning/member activation cannot reset an existing
   account. See [the exact account-access contract](account-access-contract.md).
4. Identify every affected gym/grant and whether the requester is a sole or shared
   owner. Obtain explicit authorization and an approved ownership-handoff plan
   before removing access that controls shared gym records. Never transfer access
   based only on a supplied email or remove gym-level isolation.
5. Record what personal data would be removed/redacted and what business,
   payment/membership transaction or audit records must remain, with the approved
   purpose, access controls and retention decision. No fixed period is approved;
   unresolved accounting/security/legal questions block fulfillment. Request
   intake alone never authorizes deletion of financial/history collections.
6. Obtain approval for a controlled fulfillment implementation/procedure and
   verify it on isolated synthetic accounts first. The new restricted local fulfillment service and isolated-only runner do not
   provide an automated worker, ownership-transfer mechanism or approved
   production deletion tool. Do not invent direct database commands
   or treat a status update as successful fulfillment.
7. An approved fulfillment process must verify session/grant revocation, scoped
   personal-data removal/redaction, existing photo-cleanup recovery, retained
   record integrity, backups and client cache/outbox behavior. Resolve failures
   and communicate through the approved contact before recording completion.
   Preserve minimal review/audit evidence according to the approved policy.

The public-page branding correction is now in local backend source/tests only.
It still needs a separately approved deployment; no server change is authorized
by this runbook. Neither a published support path nor actual fulfillment can be
certified until the owner completes these gates.

## Reliability verification

1. Configure encrypted, access-controlled scheduled MongoDB backups and retention. Store a recovery copy separately from the VPS; monitor failures. Cloudinary images and database references need a compatible recovery/deletion strategy.
2. Restore a backup into a separate isolated environment. Verify member counts, plan terms, fees/dues/history, user/gym isolation and representative protected photos. Record restore duration and evidence; backup existence alone is insufficient.
3. Reconcile a synthetic gym through full/partial payments, expired memberships with dues, renewals/cancellation, duplicate references, interrupted/uncertain writes, device restart and session renewal. Never use production payments for smoke tests.
4. Monitor process/database readiness, safe error/latency metrics, disk/certificate capacity, photo cleanup failures and deletion-request age. `/health` is liveness; `/ready` is database/application readiness. Protect operational access and avoid logging personal/request bodies or credentials.
5. Test the actual release install/update path, secure-storage/outbox retention and Android process death. Test low-end hardware, poor network and a 16 KB emulator/device; include photo permission failures, accessibility and keyboard clearance.

No backup schedule, restore exercise, VPS configuration, production deployment, monitoring service or data deletion has been performed by these local code changes.

## Approved deletion-intake policy

See [the approved scope and policy](scope-cleanup.md). Requests confirm receipt only. Manual review must establish legitimate retention and shared-gym ownership transfer before any removal. No fixed retention period, automatic deletion or legal-compliance claim has been approved. Verified fulfillment remains outstanding before public launch.
