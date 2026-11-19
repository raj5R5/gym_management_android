# Manual account deletion — local verified workflow

## Status change — 29 October 2026

**Historical implementation, not an approved operating procedure.** Raj has
withdrawn personal mailbox monitoring/manual fulfillment. The previous assignment
and numbered manual duties below describe the existing test-only design, not
Raj's current commitments. No substitute reviewer or unattended production
worker exists. See [automation proposal](account-deletion-automation-plan.md).
Do not enable the isolated CLI in production or present intake as completion.

27 October 2026. Assigned reviewer: **Raj** (confirmed). Backup reviewer not
assigned. Proposed acknowledgment within 2 business days / fulfillment target
30 calendar days remain **unapproved**, not legal deadlines. Category retention
criteria/periods also require approval. No real deletion request was submitted.

The public in-app/web endpoints still provide password-verified, idempotent intake
only. New internal fulfillment code is not mounted on HTTP routes, is disabled
by default and was verified against owned synthetic replica-set data only.

Backend implementation:
`src/modules/accountDeletion/fulfillment.model.js`, `fulfillment.service.js`,
`src/scripts/accountDeletionReview.js`,
`tests/integration/accountDeletionFulfillment.test.js`.

## Review and stages

1. Raj verifies identity through the password-confirmed receipt and approved
   secure support/recovery evidence. A supplied email or receipt identifier alone
   is not identity proof. Never collect passwords/tokens in support tickets.
   Record only protected evidence references, not copies of identity documents.
2. Supply evidence references for identity, ownership/handoff, approved retention
   decision and backup disposition. For each retained category (financial,
   membership transactions, minimal security/audit and pseudonymous account
   linkage), record its actual purpose and removal/review criteria. Synthetic
   test criteria are not a production retention policy.
3. `review` stores an internal case, snapshots the account/grant/photo scope and
   changes the public receipt to `in_review`. Re-review is required if registered
   identity, credential revision, grants or photo scope changes.
4. `fulfill` revalidates the case in a transaction. It blocks sole-admin gyms
   until a usable authorized successor exists; linked member/trainer records
   until their wider personal/shared-record handling is implemented; and pending
   photo operations until reconciled. It does not invent ownership transfer.
   Existing staff/handoff mechanisms need explicit review and authorization.
5. For the supported owner-only/shared-gym case, remove owner contact/photo fields,
   pseudonymize the account identity while retaining its foreign-key identifier,
   remove password/activation/recovery credentials, revoke sessions/grants and
   increment the credential revision. Other owners, members, gyms, assignments,
   plans, memberships, payments and financial/idempotency history are preserved.
   This is scoped erasure/redaction, not a claim that all database rows disappear.
6. Queue current **and historical/abandoned** owner-photo assets through the
   existing durable cleanup worker before removing obsolete operation metadata.
   The case stays `cleanup_pending` until queue entries clear. Provider failures
   retain the queue and prevent completion; no untracked Cloudinary deletion is
   performed. Referenced assets are not blindly destroyed.
7. Resolve outside-system/provider copies, backup expiry/restore handling and
   local device/recovery data under the approved policy. Scope and communicate
   justified retained data to the requester. The tool cannot independently verify
   off-app actions, legal basis or the truth of a human evidence reference.
8. Record protected off-app/backup resolution and truthful outcome-notification
   evidence. Only then `complete` verifies cleanup/redaction/access conditions
   and marks the receipt completed. Never send a success notice for an unresolved
   case or substitute a status flag for deletion. Ambiguous failures require
   rechecking the same case, not blindly repeating destructive steps.

## Isolated operator rehearsal — no production path authorized

The CLI refuses any environment other than `NODE_ENV=test` plus explicit
`ACCOUNT_DELETION_ISOLATED=1`, and any MongoDB URI other than a loopback
`127.0.0.1` owned fixture database named `gym_tests_<32 hex characters>`.
These checks run **before connection**. It does not start an HTTP server,
cleanup worker or SMTP delivery. Tests use the existing temporary-database
helper; do not point this tool at an ordinary local or hosted account database.

When a deliberately created isolated fixture is running, its operator may use:

```sh
node src/scripts/accountDeletionReview.js review REQUEST_ID PRIVATE_REVIEW_EVIDENCE.json
node src/scripts/accountDeletionReview.js fulfill REQUEST_ID
node src/scripts/accountDeletionReview.js complete REQUEST_ID PRIVATE_COMPLETION_EVIDENCE.json
```

These are command shapes, not executable real account identifiers or evidence.
The evidence schemas are defined by `reviewSchema` and `finishSchema` in the
service. The operator argument is trusted internal tooling context, never a
public client-supplied identity. Privileged backend/OS access remains necessary;
there is no user/admin HTTP completion endpoint. No production-enabled operator
tool or live retention policy is approved by this implementation.

## Acceptance and remaining release gates

Isolated tests verify assigned-reviewer/default-disable guards, required evidence,
sole-owner and unusable-successor blocking, changed scope, linked records,
uncertain operations, exact financial-record preservation, revoked old access,
idempotent fulfillment, durable photo failure/retry, orphan-asset cleanup and
completion evidence. They do not establish real provider deletion, backups or
production fulfillment readiness.

Before public launch: approve category retention/exception criteria and targets,
assign backup/escalation, implement linked-record cases or keep them explicitly
blocked with an accountable manual resolution path, verify sole-owner handoff,
approve secure operator access/tooling and rehearse the real approved operational
procedure on isolated data. Verify actual provider cleanup/backup practices and
locked-out support. Keep [backup/rollback/deployment approval](privacy-policy-deployment-plan.md)
separate; this document authorizes no production execution or data removal.
