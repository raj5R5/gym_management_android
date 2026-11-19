# Privacy policy — approval-gated deployment plan

Prepared 27 October 2026. **Plan only: nothing here authorizes execution.** The
policy remains an unapproved draft. Production deployment, database activity,
proxy changes, upload and app publication are not authorized.

Intended destination: `https://gym-api.semgroup.in/privacy-policy`.
Confirmed operator/contact: Raj / `pcterajbca7772@gmail.com`.
Read-only HTTPS inspection on 29 October 2026 found HTTP 200 serving the
unapproved draft, plus the updated MuscleDesk deletion page. See
[the current audit](release-audit-2026-10-29.md). Older 404 observations elsewhere
in this plan are historical. These observations do not authorize publication,
removal or rollback. Preserve the backup, validation and rollback steps below
for any separately approved final-policy deployment.

## Decisions needed before finalizing the text

1. **Age:** Approve account-holder eligibility and whether gyms may enter
   under-18 member records. If allowed, define guardian authorization/verification,
   gym responsibilities and required product controls. If prohibited, define how
   that restriction is communicated/enforced and existing records handled.
2. **Retention:** Approve periods or justified review/removal criteria for
   accounts, member/trainer records, financial/membership history, photos,
   recovery/operation snapshots, request/audit records, logs and backups. State
   when each period starts, exceptions and how removal/backup expiry is enforced.
   The service/legal-obligation principle is already agreed; no fixed period is.
3. **Deletion:** Name the reviewer, monitoring/escalation arrangement and expected
   acknowledgment/fulfillment timelines. Approve identity verification, sole/shared
   gym ownership handoff, what is erased/redacted versus retained and why,
   provider cleanup, backup handling and completion confirmation. Keep intake
   separate from actual fulfillment; do not automatically delete financial data.
4. **Support/recovery:** Confirm who monitors the supplied email and how requests
   from locked-out users and people recorded by a gym are verified and handled.
   Recovery APIs now exist locally, and the controlled local Gmail rehearsal
   passed (see `smtp-recovery-verification.md`). Hosted deployment/delivery still
   need verification. Email alone cannot authorize password replacement or gym
   ownership transfer. The local deletion page now offers email intake for
   locked-out users; mailbox monitoring and ownership checks need an approved
   operational procedure before publication.
5. **Providers/sharing:** Confirm actual database host (MongoDB is technology,
   not proof of Atlas), Hostinger/Cloudinary arrangements, subprocessors,
   processing locations, logs, backup/cleanup practices and any cross-border
   handling. Confirm any off-app exports, support/monitoring tools, additional
   uses or disclosures. Verify the final website/proxy's cookies/logging/tracking;
   the prepared HTML itself has no scripts or third-party assets.
6. **Final authority/text:** Confirm operator jurisdiction and any additional
   required operator details, gym/operator responsibilities, the procedure for
   privacy requests and material policy-change notices, final wording and
   effective date. Separately approve deployment/publication on the intended
   domain after confirming publishing authority. India-only launch, Raj, the
   email and intended URL are already supplied; do not request them again.

These are operational decisions, not values that source code or this plan can
invent. See [the factual draft](privacy-policy-draft.md) and
[source evidence](privacy-policy-review.md). Necessary product controls and
fulfillment/recovery work must follow the approved decisions before public launch.

Local verification update, 28 October 2026: both pages and the deletion
stylesheet return HTTP 200 for GET/HEAD using the isolated backend app.
Production still returns privacy HTTP 404 and the older deletion branding.
See [local verification](privacy-pages-local-verification.md). This does not
approve publication or change the backup, validation or rollback steps below.

## 1. Approval and release scope — before remote work

- Obtain final policy approval and separate, explicit permission for the exact
  deployment window/scope. Never deploy the current draft merely to get HTTP 200.
- Read-only inspect the actual server first: active release directory/revision,
  Node version, service manager and process working directory, bind address,
  Apache/reverse-proxy mapping, domain authority/TLS, persistent paths, startup
  configuration and latest health/readiness. These server details are not assumed.
  Record safe facts without exposing `.env`, credentials or customer records.
- Compare the live backend with the local candidate before choosing a change set.
  If they differ, prepare and validate a reviewed compatible release. Do not
  overwrite live `src/app.js` with the entire dirty local candidate or deploy
  unrelated attendance/branch/auth changes under a privacy-page approval.
- This route needs no new dependency, environment variable, database schema or
  index. Do not run migrations/index scripts for it. Normal server startup still
  connects MongoDB, creates/verifies existing indexes and starts photo-cleanup
  workers (`src/server.js`); a restart is not a read-only audit. If those effects
  exceed the approved scope, stop and resolve deployment scope first.

## 2. Final local artifact and rehearsal

- After text approval, update `docs/privacy-policy-draft.md`, its HTML export and
  source digest, and the backend's bundled HTML together. Set only the approved
  effective date; remove draft notices/noindex deliberately, not before approval.
- Required backend payload: `src/modules/privacyPolicy/privacy.routes.js`,
  `src/modules/privacyPolicy/privacy-policy.html`, and the reviewed import/mount
  in `src/app.js` at `/privacy-policy` (outside `/api/v1`). Include the route tests
  in validation. Preserve all existing local user changes and historical records.
- The current test intentionally asserts draft/noindex. When finalization is
  authorized, update it to assert approved content, effective date and absence
  of draft warnings while preserving no-auth/no-database/no-cookie and no-write
  route tests. Do not simply delete/weaken the test to pass publication checks.
- Check Markdown/export digest, asset equality, links/anchors, mobile/light/dark
  reading, accessibility and long text. Check syntax and imports without running
  `src/server.js`. Test via the existing database-free app-factory fixtures:

  ```sh
  cd /Users/semgroup/Desktop/BackendProjects/gym_management_backend
  node --check src/modules/privacyPolicy/privacy.routes.js
  node --check src/app.js
  node --test tests/integration/privacyPolicy.test.js
  npm run lint -- --no-fix
  ```

- Rehearse the exact candidate with isolated test configuration/database if wider
  backend changes are required. Never use the production `.env` or production
  database for local tests; do not launch a second production-connected server.

## 3. Backup and rollback preparation — only after approval

- Identify a healthy previous release and exact service restart/switch procedure;
  record its revision/checksums and permissions. Store the complete previous code
  release outside the incoming release directory. Do not reset/stash live work.
- Confirm a recent encrypted, access-controlled database backup and verified
  isolated restore evidence. If inadequate, obtain permission for a consistent
  backup before deploying; do not initiate backup/restore under this plan.
- Preserve `.env` and other private configuration, persistent upload directories,
  database storage and Cloudinary data/references. Keep protected recovery copies
  of necessary configuration outside deployment artifacts; never print secrets,
  package them in the release or replace them with local defaults. Confirm free
  space and restore ownership/permissions. Do not delete or recreate collections.
- Record health/readiness and safe route statuses before deployment. Prepare a
  rollback trigger: startup/readiness failure, privacy content/HTTP/TLS failure,
  protected-route regression or unexpected sanitized service errors.

## 4. Controlled release — future authorized action only

- Stage the complete reviewed code/assets into a new release directory using the
  existing verified deployment method. Never copy local `.env`, `node_modules`,
  signing files or Flutter production config to the backend. Keep existing
  dependencies when unchanged; any clean release install must use the lockfile
  and compatible Node version, not upgrade packages.
- Validate syntax, file permissions, asset/checksum and module presence before
  switching the active release. Use only the identified service manager and an
  explicitly approved switch/restart; do not invent a PM2/systemd service name.
- Check whether Apache already forwards this root-level path. Do not assume the
  `/api/v1/` mapping covers `/privacy-policy`. If not, stop and obtain separate
  reviewed proxy-change approval, save its previous configuration and validate
  syntax before any separately authorized reload. Keep API/deletion routing,
  forwarding-header rules, TLS and private Node port protections unchanged.

## 5. Validation and public HTTPS verification

- Verify the intended Node service is running from the reviewed release; inspect
  sanitized startup logs. Check `/health`, `/api/v1/health` and `/ready` through
  the established topology. Liveness alone is insufficient; do not weaken
  readiness/authentication just to make a smoke test pass.
- Verify `GET https://gym-api.semgroup.in/privacy-policy` without credentials:
  trusted valid TLS/hostname, HTTPS-only redirects, HTTP 200 `text/html`, correct
  MuscleDesk/Raj/contact/effective-date content, no draft markers, no login,
  cookie/banner requirement or geographic restriction. Verify HEAD, no-store and
  security headers too. Do not use `curl -k` or disable certificate checks.
- Read it in a private browser and at mobile widths; check all links and the
  app's Privacy & support launch path. Compare the served document with the
  approved local artifact. Public accessibility does not itself certify accuracy.
- Use read-only GET checks for API health and the public account-deletion page;
  do not submit deletion requests, credentials, payments or member changes as
  production smoke tests. Use an isolated account/database for write-flow QA.
- Run the existing public preflight from the Flutter project (read-only GETs):

  ```sh
  python3 tool/play_release.py --config release/production.json --check-urls --ca-file /etc/ssl/cert.pem
  ```

## 6. Rollback if validation fails

- Restore the previous code release via the prepared service-manager procedure;
  preserve private configuration, uploads and all database/history collections.
  Revert a proxy change only if separately authorized and actually made; validate
  before its reload. Recheck health/readiness and existing API/deletion routes.
- Do not automatically restore the database for a static-page failure: that can
  erase legitimate writes since backup. Unexpected database effects require
  investigation and separately approved recovery, never a blind rollback script.
- A rollback may restore HTTP 404 at the new page. Leave the AAB workflow blocked
  until the approved page is served again. Record sanitized evidence and outcome;
  do not claim a failed deployment or missing policy is ready for release.

## 7. Signed bundle and separate Play publication gates

After approved publication and successful public checks, from the Flutter project:

```sh
python3 tool/play_release.py --config release/production.json --check-urls --ca-file /etc/ssl/cert.pem --build
```

The helper requires URL checks for a build, rejects an explicitly unapproved
privacy page, runs analysis/full Flutter tests, builds the signed AAB and verifies
signature/required ABIs/native ELF alignment. It never uploads. Expected output
after success: `build/app/outputs/bundle/release/app-release.aab`.

```sh
python3 tool/play_release.py --verify-bundle build/app/outputs/bundle/release/app-release.aab
shasum -a 256 build/app/outputs/bundle/release/app-release.aab
```

No successful signed build or checksum is claimed now. The private upload key and
ignored signing properties are already configured; do not replace or expose them.
The candidate ID `com.semgroup.gymmanagement` is locally configured, not proven
available by local inspection. Confirm its Play Console ownership/history before
the first upload (preferably before the final build), plus version/signing setup.

A signed artifact is not permission or readiness to publish. Before public release
resolve actual deletion fulfillment (not just intake), approved recovery/support
and minors/retention controls, Data safety/audience/content declarations, listing
assets and reviewer access, Console testing requirements and release-device QA
(including 16 KB runtime). See [the release checklist](play-release.md).
Google requires an accessible accurate privacy policy and account/data-deletion
support where account creation is offered:
[User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311),
[account-deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111).
This plan does not claim legal compliance or guarantee Play approval.

## Local candidate addendum — recovery/age/manual-review feature pass

The preceding backup, validation, rollout and rollback steps remain unchanged.
The local backend now also imports recovery modules and registers an internal
fulfillment model. **Do not deploy the newer `src/app.js` with only the three
original privacy files.** A complete feature candidate also requires:

- `src/modules/passwordRecovery/`, `src/modules/members/member.age.js`, the
  member/photo/account age gates, credential-revision changes in auth/account/
  session models, config/logger/error changes and reviewed startup/shutdown/index
  changes in `src/server.js`.
- `src/modules/accountDeletion/fulfillment.model.js`, `fulfillment.service.js`
  and isolated-only `src/scripts/accountDeletionReview.js`. No public completion
  endpoint exists, and the runner rejects production/remote databases.
- `package.json` and lockfile for pinned Nodemailer `10.2.1`. Preserve private
  `.env`; missing mail credentials intentionally leave recovery unavailable.
  Never copy the local private `.env` or silently enable mail/fulfillment.
- The intended `PasswordRecovery` TTL index is handled by normal startup. No
  migration/drop script is authorized. Legacy account/session revisions default
  to zero, with no bulk rewrite. Review startup/cleanup effects before restart.

For privacy-only deployment, prepare/test a minimal patch against the verified
live base. Do not ship these feature changes under privacy-only approval. For a
full feature deployment, obtain separate scope approval and stage the complete
candidate using the same backup/rollback discipline. No deployment, restart,
migration or production configuration action occurred in this pass.
