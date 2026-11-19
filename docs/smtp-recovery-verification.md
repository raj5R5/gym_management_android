# SMTP and local recovery verification — 28 October 2026

Scope: existing recovery implementation, newly supplied local SMTP credential,
owned temporary database and recipient explicitly approved by Raj as the test
inbox. No production account, database, API, deployment or deletion request used.
No password, recovery code, bearer/refresh token or raw SMTP response is recorded.

## Configuration and commands

Required backend `.env` names: `RECOVERY_SMTP_USER`, `RECOVERY_SMTP_PASSWORD`,
`RECOVERY_EMAIL_FROM`, `RECOVERY_TOKEN_TTL_SECONDS`. All were present and passed
`loadConfig` validation. User/from matched the approved Gmail identity; configured
TTL was 900 seconds. The file remained Git-ignored, mode 600 and byte-for-byte
unchanged during the rehearsal.

The application's `createRecoveryDelivery` transport options were reused:
`smtp.gmail.com:465`, TLS enabled, certificate verification enabled, minimum TLS
1.2, SMTP logger/debug disabled, file/URL content access disabled. Nodemailer's
`verify()` passed connection/TLS/authentication; it sent no email.

```sh
npm run lint -- --no-fix
node --test tests/integration/passwordRecovery.test.js tests/integration/auth.test.js tests/integration/foundation.test.js
```

Lint passed; **67 tests passed, 0 failed/skipped** using synthetic delivery and
the existing owned loopback MongoDB helper, without loading real SMTP/database
settings into those tests. No package/configuration or application-source edits
were needed for this verification pass.

## Controlled real-SMTP rehearsal

- Used actual `startServer`, not a mock HTTP router. Bound only to loopback on an
  OS-assigned port. The configured `.env` database URI was **not used**. Only the
  four mail fields were selected; fresh isolated JWT settings and the helper's
  owned temporary MongoDB replica-set URI were supplied. Photo providers and
  bootstrap were disabled. Readiness returned 200.
- Created one synthetic owner/gym through the real local registration endpoint;
  the approved inbox address identified that disposable account only. Random
  initial/replacement passwords were held in process memory and never displayed.
- Sent exactly **two recovery-code messages and one password-change notice** to
  the explicitly approved test inbox. Real Gmail SMTP accepted all three.
- The isolated transport observer retained sent proofs only in memory to exercise
  the local reset endpoint. It did not retrieve the codes from the inbox, expose
  them via API, persist them, change the delivery implementation or bypass proof
  validation. Manual inbox receipt is a separate check below.
- All **39 rehearsal checks passed**. Generic request acceptance was 202, without
  a raw code. The stored proof was a digest and its expiry matched the configured
  15-minute lifetime. An expired fixture proof returned 401 and did not change
  the password. The second valid proof returned 200 with `passwordChanged:true`.
- Replay of the consumed proof and login with the old password returned 401.
  Both pre-existing access sessions and both refresh sessions were rejected after
  reset. New-password login and its authenticated `/auth/me` returned 200.
- Gym, grants, membership and financial snapshots remained unchanged. The local
  backend shut down normally and the owned temporary database/files were removed.
  Test codes/passwords no longer correspond to a running account database.

## Exact limits / manual checks

**Expiry:** verified the real generated 900-second deadline, then expired only
the owned fixture row to test HTTP rejection. This was not a 15-minute wall-clock
wait. Natural expiry passage/TTL background deletion were not independently
timed in this rehearsal; database TTL cleanup is distinct from credential-use
expiry enforcement.

**Delivery:** SMTP accepted all three messages, and Raj explicitly confirmed
receipt of both recovery messages and the password-change notice. Folder/thread
placement was not separately reported. This recipient confirmation is separate
from SMTP acceptance; no human copied the code into the Flutter app in this test.

**Production/platform:** no hosted recovery POST, production data operation,
phone installation, Flutter UI email-to-reset interaction, deployment or release
build was performed. Provider locations/retention/backup practices and reliability
under load remain unverified. Privacy approval/publication and all other release
guards remain outstanding and unchanged.

The reusable scratch rehearsal and sanitized results are in `/tmp/` for this
session; they are not installed production controls. Any repeat mail test needs
an explicitly approved recipient/message plan. No real mail was sent by the
automated backend suite.
