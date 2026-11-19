# Local privacy/deletion page verification — 28 October 2026

Local preparation only. The privacy policy remains a draft; no publication,
deployment, real deletion request, email, release build or Git write was performed.

## Confirmed routing and hosted difference

- `backend/src/app.js` already imports `createPrivacyPolicyRouter` and mounts it
  at `/privacy-policy` before not-found handling, outside the database-dependent
  routes. `src/modules/privacyPolicy/privacy.routes.js` serves its fixed bundled
  HTML asset. No additional privacy endpoint or application mount was needed.
- Public deletion is already mounted at `/account-deletion` when database-backed
  routes are constructed. Its CSS lives at `/account-deletion/style.css`.
- Fresh unauthenticated HTTPS GETs returned privacy **404**, JSON `NOT_FOUND`,
  and deletion **200** with `Gym Management · Account deletion`, without the
  support email or privacy link. No production POST or database call was made.
- The local mount/asset work, so the live service is not serving the equivalent
  candidate at these paths. An older/incomplete release or different root-path
  routing is plausible. The active server files/process and proxy configuration
  were not inspected: the exact remote cause is **not confirmed**.
- A future approved deployment must include the reviewed router, HTML asset and
  mount/import, plus all dependencies of that selected backend candidate. Do not
  copy `app.js` alone or deploy unreviewed unrelated changes. The existing plan's
  backup, staged release, HTTPS validation and rollback requirements still apply.

## Local changes

- Backend `src/modules/accountDeletion/routes.js`: support address, same-origin
  privacy link, prominent email option for users unable to provide a password,
  explicit form target and responsive Iron Signal styling. Existing password
  verification, rate limit, request receipt and financial behavior are unchanged.
- Backend `tests/integration/accountDeletion.test.js`: page/receipt links,
  password-free option wording, GET/HEAD/CSS checks and read-only assertions.
- `docs/privacy-policy-draft.md`, `docs/privacy-policy/index.html` and backend
  `src/modules/privacyPolicy/privacy-policy.html`: corrected stale local SMTP
  facts, qualified email-request data handling and linked deletion on the same
  origin. Draft/noindex warnings and all unresolved declarations remain.
- `docs/privacy-policy-deployment-plan.md`: updated the stale recovery fact and
  linked this local result; deployment/backup/rollback safeguards remain intact.

## Checks actually run

From the backend repository:

```sh
node --test tests/integration/privacyPolicy.test.js tests/integration/accountDeletion.test.js
npm run lint
git diff --check
```

Final result: **16 tests passed, 0 failed/skipped; ESLint passed; diff check passed.**
Tests create only owned temporary MongoDB fixtures with synthetic accounts;
no `.env`, production database or real email transport is used.

The actual backend `createApp` also ran on loopback behind a scratch GET/HEAD-only
preview harness with an owned, empty disposable MongoDB and disabled delivery.
GET and HEAD for both pages and the deletion stylesheet returned **200**, the
expected HTML/CSS content types and `Cache-Control: no-store`; no cookie was set.
The documentation HTML and bundled asset are byte-identical, and the Markdown
source digest matches the HTML metadata. Flutter/build checks were unnecessary:
no app, dependency, release configuration or signing change was made.

Browser inspection covered 320px and 390px mobile frames, light/dark styles,
wrapping, the support/email action and existing form. No horizontal overflow
was detected. Narrow full-page inspection and navigation between privacy and
account deletion passed; all 11 policy contents anchors had existing targets.
A configured mail application was not opened, and no form or email was submitted.
This is browser verification, **not Android/iOS device verification**. Screenshots
are local review artifacts under the Codex visualization folder, not app assets.
The owned preview/database were stopped and disposed after verification.

## Still awaiting confirmation / approval

- Final policy wording/effective date and publication authority; retained draft
  markers must not be removed merely to satisfy the release guard.
- Actual provider/database processing locations, Cloudinary deletion/retention,
  infrastructure log/backup retention and any off-app data handling.
- Category retention criteria/exceptions, monitoring of Raj's support inbox,
  locked-out identity verification, ownership handling, backup reviewer and
  acknowledgment/fulfillment targets. An email opens a request channel; it does
  not itself verify ownership, create a backend receipt or complete deletion.
- Verification of the approved age restrictions and recovery flow in the hosted
  release, followed by separately approved deployment and public HTTPS checks.

See `privacy-policy-deployment-plan.md` before any future remote work. Nothing in
this verification authorizes deployment, an AAB against the draft, or publication.
