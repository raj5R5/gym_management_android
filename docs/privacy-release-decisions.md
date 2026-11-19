# MuscleDesk privacy release decisions

## Final decisions — 29 October 2026 (supersede everything below)

Raj approved finalizing the policy: no personal spreadsheet copies, sale or unrelated
use; MongoDB Atlas (records), Cloudinary (photos) and Gmail (recovery, deletion and
support email); Raj personally reviews and fulfils deletion requests submitted in the
app, on the web page or by email; purpose-based retention with deletion on a fulfilled
request except the specific records listed in policy section 7; no invented legal
obligations or fixed periods. The local policy files are final with effective date
October 29, 2026 — change the date if publication happens later. Publication,
deployment and upload each still need separate authorization.

## Superseding owner decisions — 29 October 2026

Raj does **not** intend to monitor a mailbox or manually fulfill privacy/deletion
requests; the earlier reviewer assignment and proposed manual commitments below
are withdrawn. MongoDB Atlas is owner-confirmed and consistent with local SRV
configuration. Cloudinary and Gmail integrations are verified in code; actual
production provider settings/regions/retention remain unverified. The owner
reports no personal customer-data copies or planned personal spreadsheet exports,
and no intended sale/unrelated personal use. Service processing remains necessary.
Retention direction: service/necessary gym records, then delete account-associated
data on a valid request except specific documented justified exceptions; no fixed
period or blanket legal financial retention. Existing intake is not unattended
fulfillment. See [automation options and remaining decisions](account-deletion-automation-plan.md).
No new reviewer, automatic-deletion implementation or publication is approved.

## Latest status — 29 October 2026

The [current audit](release-audit-2026-10-29.md) supersedes historical status
statements below: the public privacy draft and updated deletion page are now
reachable; the draft is **not approved**. The protected deletion-status route
returns 401. Local Gmail delivery was confirmed by the approved test recipient;
SMTP is no longer an untested local feature. Hosted recovery/reset, deletion
fulfillment, provider facts, retention/response targets, effective date and final
policy approval remain unresolved. No new owner decisions are inferred from
successful deployment or passing tests. Backup/rollback steps remain in the
existing deployment plan; no production action is authorized here.

27 October 2026. Internal checklist, **not an approved policy or deployment
authorization**. Raj, `pcterajbca7772@gmail.com`, the intended privacy URL and
India-first launch are already confirmed. The package ID is a Console candidate.
Evidence for each draft statement is in [the evidence register](privacy-policy-evidence.md).
Keep [the deployment/backup/rollback plan](privacy-policy-deployment-plan.md) intact.

## Confirmed implementation decisions and current status

Raj subsequently approved local implementation: adult account holders; under-18
member records only after guardian authorization/verification/access/handling
controls exist (interim workflow disabled); optional photos; necessary gym/service
provider use without ads/unrelated sharing; manual fulfillment; and the proposed
isolated recovery API. Raj is the assigned deletion reviewer, backup unassigned.
Gmail sender `pcterajbca7772@gmail.com` was selected, private credential left blank.
Rows below retain proposal history; they do not override these newer decisions.

- **A1/C1:** Owner signup requires an adult declaration. Known-minor registration,
  profile changes, new photo upload and member-account provisioning/activation
  are locally blocked using gym-calendar DOB checks. Reads, photo removal and
  committed receipts/financial recovery remain available. Missing DOB is still
  optional/unknown, not verified adulthood. No guardian workflow is enabled.
- **A3/C4:** [Restricted manual fulfillment](manual-deletion-workflow.md) and an
  isolated-only operator tool now exist and have synthetic acceptance tests.
  Sole-owner/linked-record/pending-operation cases stop safely. No public
  completion endpoint, production tool, retention policy or automatic worker
  is claimed. Proposed response/retention targets remain unapproved.
- **A4/C3:** [Approved new recovery contract](password-recovery-contract.md),
  Gmail TLS adapter and Flutter flow are implemented locally and tested using
  synthetic delivery. Private SMTP credential, actual delivery and deployment
  are not verified. Missing delivery returns unavailable, not fake success.
- **A5/B2:** No ad/analytics/unrelated-sharing integration was found in the code/
  dependency reinspection. Gmail email delivery adds a necessary provider data
  flow; Cloudinary, database/hosting, mail terms/locations/retention and off-app
  practices remain unverified. Declared intent is not proof of provider behavior.
- **A2/A6:** Category retention, targets, backup reviewer/escalation, jurisdiction,
  provider facts, final wording/effective date and publication approval remain
  unresolved. Do not adopt the historical proposed numbers automatically.

## A. Remaining approvals and already approved directions

| ID | Decision needed | Proposed conservative launch default — approval required |
| --- | --- | --- |
| A1 | Adult account holders and interim under-18 block are approved. Future guardian authorization/verification, unknown-DOB handling and existing-record procedure need review | Known-minor gate is implemented locally; no guardian workflow or independently verified age assurance is claimed. Keep DOB optional without treating missing DOB as adulthood; do not silently enable minors |
| A2 | Category retention/removal criteria, start points and exceptions | Retain only what the service and justified accounting/security obligations require. No indefinite blanket retention. Approve a category schedule before launch. Suggested **30-day operational-log and rolling-backup windows** are discussion proposals only, subject to provider capabilities/incident and accounting review; they do not determine financial, audit or deletion-evidence retention or authorize deleting anything |
| A3 | Raj is the assigned reviewer. Backup, monitoring/escalation, response targets and retention/ownership criteria remain open | Restricted local manual fulfillment is tested. Proposed acknowledgment within 2 business days / fulfillment target 30 calendar days remain unapproved service targets, not legal deadlines. No automatic cascade or production execution |
| A4 | New isolated API and Gmail sender are approved. Private credential/account eligibility, actual delivery and support escalation still need verification | TLS SMTP adapter and client flow exist locally; random expiring single-use proof and credential-revision/session safeguards are tested. No real mail, production reset or support-assisted recovery is verified |
| A5 | Necessary gym/service-provider operations without ads/unrelated sharing are approved direction; actual providers/off-app practices need evidence | Source/dependency inspection found no ad/analytics integration. Gmail is a new necessary email flow. Do not turn the approved restriction into an unverified blanket provider-practice claim |
| A6 | Jurisdiction/additional operator details, privacy-request handling, change notices, final wording/effective date and publishing authority | India-only distribution; plain-language contact and change notice; no unverified India-only storage or compliance promise. Finalize text only after A1–A5 and technical verification. Separate explicit publication/deployment approval; a supplied URL is not that approval |

Do not approve a default that cannot be operated or enforced. If rejected, record
the alternative and affected controls before revising the draft. No age limit,
retention schedule, reviewer appointment, deadline or recovery-token lifetime
above has been implemented or added to the public draft.

## B. Technical facts — verify evidence, do not ask Raj to guess

- [ ] **B1 Live candidate parity:** Compare deployed revision/modules/configuration
  names with local source, using separately authorized read-only access. The last
  privacy result was 404; historical deletion GET 200/unauthenticated status 401
  do not verify request persistence or fulfillment. Confirm any deployed recovery
  contract rather than inventing endpoints. No fresh remote verification here.
- [ ] **B2 Providers:** Inspect approved account settings/contracts privately for
  Hostinger region/services, actual MongoDB hosting/topology, Cloudinary delivery,
  storage/cleanup and subprocessors. Technology/library names do not prove host,
  location, contract terms, encryption at rest or retention. Record safe facts,
  never credentials or database/customer contents.
- [ ] **B3 Data lifetime/security:** Verify effective session/activation TTLs and
  existing indexes, backup/log locations and expiry, restore proof, encryption
  and access controls. Local schema TTLs prove intended configuration, not live
  index existence or prompt removal. Check proxy/provider logs separately.
- [ ] **B4 Website:** Verify control/publishing authority, Apache root-path routing,
  TLS, public access, logs/cookies/analytics and approved document checksum. Local
  script-free HTML does not establish the proxy/website's complete practices.
- [ ] **B5 Release artifact/Console:** Confirm package availability/history,
  version/signing association, target audience/India distribution and developer
  account testing requirements. Locally configured ID/signing is not Console
  ownership. Inspect final release permissions/dependencies and real-device
  behavior; source configuration is not artifact/runtime proof.

Provider/business practices absent from source require account/contract records
and operator confirmation. Do not relabel them verified because a form is checked.

## C. Must exist before public launch — outcome and acceptance evidence

| ID | Required feature/procedure | Current state / minimum acceptance |
| --- | --- | --- |
| C1 | Approved audience/minors controls | Known-DOB member gates and owner declaration implemented locally; no guardian workflow. Missing DOB/independent age verification and deployed parity remain limitations. Historical reads, photo removal and financial recovery preserved |
| C2 | Retention and privacy-request procedure | Schedule/owners/enforcement not finalized. Implement category review, controlled removal/retained-record restrictions, backup-expiry and restore handling; prove on isolated records that deleted personal data is not silently reintroduced by restore. A policy statement is not enforcement |
| C3 | Functional password recovery and locked-out support | Approved local API, Gmail adapter and Flutter flow have synthetic acceptance tests. SMTP credential, real delivery, supported-account verification and hosted availability remain open. Support email alone is insufficient |
| C4 | Actual deletion fulfillment and monitoring | Restricted internal owner-only workflow and isolated runner are tested. Default disabled; no public completion route. Sole-owner, linked-record and pending-operation cases stop. Approved retention/targets, wider-case resolution, production operator access and real provider/outside-system evidence remain gates |
| C5 | Approved accurate policy/public links | Draft and hosted 404 remain. After decisions and separate deployment approval, synchronize Markdown/HTML/backend asset, approve effective date, revise draft-state tests, publish through the preserved plan and verify public HTTPS without login |
| C6 | Isolated end-to-end and store/release QA | Verify recovery, deletion, tenant isolation, replay/error handling and release install/session/financial safeguards using synthetic accounts. Complete accurate Data safety/audience/listing, Console tests and device/16 KB QA. No production write tests or publishing are authorized |

## Minimum functional recovery — proposed security design, no invented API

1. Reachable “recover access” path while signed out and monitored escalation for
   failed delivery/inaccessible mailboxes. Do not ask users to send passwords,
   tokens or identity documents in ordinary email. Define proportional secure
   verification and refusal/escalation for unprovable ownership; never grant gym
   access merely from a supplied email or someone else's gym records.
2. An approved backend recovery contract and mail-delivery provider. Request
   responses must not enumerate accounts (consistent message/timing); use per-IP
   and per-account throttling, abuse controls and safe diagnostics. Do not lock
   accounts, modify passwords or revoke sessions merely because reset is requested.
3. Cryptographically random, account/purpose-bound, expiring credentials stored
   only as digests, with bounded attempts and atomic single-use consumption.
   Existing expired/used credentials must fail; do not log raw codes/links. Use
   approved HTTPS destinations without arbitrary redirect targets. Avoid tokens
   in referrers, third-party assets, analytics or support messages.
4. Accept a new password only after proof, apply the existing password policy and
   hash function, commit password/token state safely and revoke existing sessions
   at successful completion. Handle concurrent reset/refresh, ambiguous responses
   and retries without reusing a consumed credential or bypassing authorization.
5. Notify the account holder of the change; do not send a password or sign the
   user in automatically. Verify subsequent login, rejection of old password/
   old sessions, wrong/expired/replayed proofs, enumeration resistance, delivery
   failure, tenant isolation and network interruption on isolated accounts.

Mailbox possession is not automatically authority to transfer a shared gym or
change the account's registered email. Those need the approved ownership process.
If self-service delivery is deferred, a support-assisted alternative must still
provide a secure, implemented, tested recovery mechanism. None exists now; do
not label the email-only fallback “working recovery.” These are product/security
release criteria; the cited Play policy does not impose a universal named
Forgot Password API. Security reference:
[OWASP Forgot Password](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).

## Minimum deletion process — intake plus real fulfillment

Keep the existing password-verified in-app/public intake, duplicate-request
protection, receipt and truthful “received” wording. Add a secure route for
locked-out people through approved recovery/support verification. Privileged
queue access must remain scoped to accountable operators; no public queue.

After verification, establish sole/shared gym ownership and an approved handoff;
identify account-linked data versus other people's gym/financial records. Apply
the approved category retention decisions, not an automatic deletion of business
history. Provide retained categories/reasons/periods or criteria to the requester.
Revoke sessions/grants, remove or redact in-scope personal data and photos through
existing durable cleanup, address provider copies, unresolved local recovery and
backups, and verify retained records remain accurate/access-restricted. Do not
blindly purge outboxes and create duplicate-payment risks.

Record minimal protected review/verification evidence, retry incomplete cleanup,
notify the requester of the real outcome and mark complete only after the
approved scope is fulfilled. Verify replay, sole/shared owners, failed cleanup,
retained history and revoked access on isolated accounts. A manual procedure
with controlled tooling and proof may suffice; automatic deletion is not claimed
or required by this plan. Google requires an in-app and external deletion path
and deletion of associated data, subject to justified disclosed retention:
[account-deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111).

## Priority / next actions

1. **Raj:** approve/revise A1–A6; identify where approved provider/configuration
   evidence for B2–B4 can be verified without posting secrets. Confirm package ID
   availability/history in Play Console before final release/upload.
2. **Technical follow-up:** verify B1–B5 using authorized read-only inspection;
   agree the recovery API/provider and scoped implementation/fulfillment plan.
3. **Implementation after decisions:** complete C1–C4 and isolated acceptance
   tests. Do not invent endpoints, write production data or change policy
   assertions to conceal missing features.
4. **Content/publication, separately authorized:** finalize evidence-based text
   and C5, preserving the existing backup/validation/rollback steps. Verify the
   final public page rather than deploying the draft to get HTTP 200.
5. **Signed artifact:** use the existing guarded `--check-urls --build` command
   only after policy approval/publication. It runs analysis/full Flutter tests,
   builds and verifies the bundle. Signing/metadata are already configured; full
   build success and checksum are still unverified. No AAB is built here.
6. **Before upload/public launch:** C6, fulfillment/retention/support readiness,
   Console identity/signing and accurate declarations remain independent gates.
   A signed AAB does not certify those operations or authorize an upload.

The last privacy 404/unapproved text blocks the checked build. Operator decisions,
provider facts and C1–C4 are accuracy/public-release gates, not all compiler checks;
they must not be concealed by changing build flags or wording. No deployment,
production mutation, key generation, app build, publication, commit or push is
authorized by this checklist.
