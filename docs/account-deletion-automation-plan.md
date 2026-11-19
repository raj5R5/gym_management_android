# Account deletion without routine manual handling

**Superseded, 29 October 2026:** Raj will review and fulfil deletion requests
manually. The release uses request intake plus the operator tool and worker
(`ACCOUNT_DELETION_AUTOMATION=operator`); see backend `docs/production-operations.md`.
The self-service automation remains in the code, off. Approved: explicit sole-owner
closure deletes all gym records; payments in continuing gyms stay, unlinked. The text
below is the original proposal, kept for history.


29 October 2026. Inspection and proposal only. No automation implemented or
production operation authorized. Raj has withdrawn the earlier manual-reviewer
assignment and does not intend to monitor privacy/deletion correspondence.

## Confirmed provider evidence

- Owner identifies MongoDB Atlas for application data. Local `.env` inspection
  found MongoDB SRV and an Atlas hostname suffix; no URI/credential was printed
  and no database connection was made. `src/config/database.js` uses Mongoose.
  Actual production cluster parity, regions and backup settings remain unverified.
- `src/modules/memberPhotos/photo.storage.js` uses authenticated Cloudinary image
  uploads and `destroy(..., invalidate: true)`. Provider `ok`/`not found` responses
  are accepted; this is not evidence of deletion from backups or every provider copy.
- `src/modules/passwordRecovery/recovery.delivery.js` uses Gmail SMTP with TLS.
  Local delivery was previously verified. Hosted delivery, mailbox retention,
  support monitoring and provider regions are not established by this code.
- No separate operator personal copies or personal spreadsheet exports are
  reported. No intended sale/unrelated personal use is declared. This is owner
  evidence, not a claim that the app does not process personal information.

## What exists, and why it cannot run unattended

Backend paths below are relative to
`/Users/semgroup/Desktop/BackendProjects/gym_management_backend`.

| Evidence | Actual behavior / gap |
| --- | --- |
| `src/modules/accountDeletion/routes.js`, `service.js`, `model.js` | Password-verified in-app/web intake; unique durable request per account, status/reference. No job dispatch, deletion or completion notice |
| `src/app.js`, `src/server.js` | Registers intake and fulfillment model only. Starts photo cleanup workers, not account-deletion fulfillment |
| `src/modules/accountDeletion/fulfillment.service.js` | Disabled by default; requires assigned reviewer and identity/retention/ownership/backup evidence references. Test-only supported owner scope removes contact/photo/password, pseudonymizes identity and revokes access |
| Same service | Blocks sole-owner gyms, linked member/trainer records and unresolved photo operations. Preserves gym/member/financial/idempotency records. Requires all four retained-category explanations; not a selective retention engine |
| `src/scripts/accountDeletionReview.js` | Refuses production/remote databases; only operates on explicitly named disposable loopback test databases. Do not weaken this guard to create an apparent production solution |
| `fulfillment.service.js` completion | Requires human notification/off-app evidence references and cleared photo queue. It does not send a deletion-completion email or verify backup erasure |
| `src/modules/memberPhotos/photo.service.js` | Durable photo cleanup retries, reference checks and delayed retry after failures are reusable. No account-level dead-letter resolution or accountable escalation |
| `src/modules/gyms/gym.model.js` and linked records | Gym contacts may themselves contain the departing owner's personal contact information. Leaving shared gym data unchanged is not proof that all account-associated personal data is removed |

Merely recording `requested` forever, disabling an account, or replacing an email
with a pseudonymous identifier is not proof that associated personal data was
deleted. Pseudonymous links can remain personal data. Most newly registered gyms
have a sole owner, so the existing handoff block is a core product case, not just
an unusual exception. Backup/log/provider copies have no verified account-erasure
integration or approved retention schedule in the inspected implementation.

## Smallest practical solution

The least new code would use a delegated accountable reviewer with a supported
production tool and verified operational procedures; Raj need not personally do
the work. The current test-only tool would still need an approved production
design. If routine manual handling is unwanted, recommend **automated normal
cases plus a delegated exception service**, reusing existing safeguards:

1. **Verify and confirm:** reuse current password verification or successful
   recovery. Add an explicit destructive-scope preview and purpose-bound,
   expiring single-use confirmation. GET links must never perform deletion.
   Recovery proof must not be silently repurposed as deletion authorization.
   Existing email-only requests are not verified ownership. Provide a secure
   external self-service path so uninstalling or losing an app session is no barrier.
2. **Determine ownership and scope:** distinguish the account from each gym and
   other people's records. For shared gyms preserve other owners' access and
   legitimate shared data; explicitly handle the departing person's contact data.
   For a sole owner offer an accepted, authorized ownership handoff or a separately
   confirmed gym-closure process, subject to owner approval. Never leave a sole
   owner blocked indefinitely or silently delete everyone's gym data.
3. **Persist a recoverable job:** store scope/policy version and confirmation
   receipt; acquire leases, perform transactional state transitions and fence
   concurrent profile/payment/photo writes. Revalidate scope before destructive
   actions. Reuse session revocation and transaction/idempotency protections.
   Reconcile uncertain financial operations before removing their recovery records.
4. **Apply selective erasure/retention:** inventory account links, member/trainer
   identities, gym contact fields, photos, operation snapshots, audit/security
   records and support messages. Remove unnecessary personal fields; retain only
   approved categories with a specific purpose and removal/review criterion.
   Do not automatically exempt all financial records or invent legal obligations.
5. **Resolve providers and backups:** enqueue current/historical/abandoned photos
   through existing cleanup; keep failures retryable and measurable. Verify Atlas
   snapshot/PITR expiry and any relevant Cloudinary backup settings, logs and
   Gmail correspondence handling. Restores need deletion replay/suppression so
   erased identities are not reintroduced. No fixed provider retention is assumed.
6. **Report truthful progress:** distinguish verification, ownership action,
   processing, retry/exception and completion. Use a restricted status capability
   after normal account access is revoked. Persist notification delivery/retry;
   send no password/token in notices. Declare completion only after required
   erasure and approved retained-copy handling are accounted for, with a truthful
   explanation of retained data. A failed worker is not a completed deletion.
7. **Handle exceptions:** alert an assigned person or contracted service for
   lost-mailbox identity disputes, ownership disputes, persistent provider failures
   and privacy complaints. Automation cannot establish legal retention grounds or
   resolve every disputed identity. Self-service access/correction can reduce
   work but does not eliminate the need for accountable exception handling.

No new API endpoints are claimed to exist. Before implementation, specify and
review the confirmation/status contracts, job states, authorization and failure
semantics. Do not expose the current reviewer/evidence parameters to app clients.

## Remaining owner decisions only

1. Who or which contracted service handles exceptions and privacy complaints if
   Raj will not? Alternatively select a delegated manual service for all requests.
   If nobody is responsible, reliable public launch remains blocked.
2. Approve sole-owner behavior: secure accepted handoff and/or explicit gym closure
   with an approved treatment of member/trainer/financial records. No silent cascade.
3. Identify specific retention exceptions: categories, documented purpose and
   end/review criteria. The service-need principle is already approved; no universal
   period or blanket financial exemption is requested or assumed.

Regions, backup configuration and provider cleanup capabilities are technical
verification tasks requiring account/configuration evidence, not guesses or
reconfirmation of provider names. Final text/date approval follows verified
implementation; October 29, 2026 remains only a proposed date, not an effective
date to backdate if approval occurs later.

## Acceptance required before describing deletion as automatic

- Owned isolated fixtures: password/recovery identity proof, expired/replayed
  confirmations, CSRF/rate limits, cross-gym/role denials and concurrent requests.
- Shared/sole-owner and multiple-gym cases, accepted handoff/closure, linked
  members/trainers, other owners and unaffected financial records.
- Worker crash/restart, duplicate jobs, changed scope, ambiguous commits and
  concurrent payment/photo activity without orphaned photos or duplicated payments.
- Selective retained-category behavior, old-session revocation, encrypted or
  capability-protected status access and minimal audit data.
- Cloudinary failure/retry and missing assets, notification failure/retry,
  backup restoration rehearsal and inability to complete with unresolved work.
- Alert/exception acceptance by the assigned operator/service and truthful
  status/completion communication. Mocked provider tests alone are insufficient
  evidence of actual provider/backup deletion behavior.

Until these gaps are resolved, the policy stays draft and Play submission stays
blocked. Preserve the existing deployment backup/validation/rollback plan.
Official reference:
[Google Play account deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
