# Android / Play release

Status (27 October 2026): **public metadata is now configured** with publisher/operator Raj, the confirmed support email and the intended API-domain privacy URL (exact values below). The policy/route remain local drafts, not approved for deployment or publication; the URL-checked release workflow still needs a reachable final policy. The Android candidate `com.semgroup.gymmanagement` needs the owner's Play Console availability/history check. A private upload key is configured. Nothing is uploaded by these tools; debug app ID/data are retained.

## Public configuration

The Git-ignored local `release/production.json` now contains `PUBLISHER_NAME=Raj`, `SUPPORT_EMAIL=pcterajbca7772@gmail.com` and intended `PRIVACY_POLICY_URL=https://gym-api.semgroup.in/privacy-policy`; `release/production.example.json` mirrors these confirmed public values. Publication is not approved. These files contain public values only; the exact allowlist rejects unexpected fields so secrets cannot accidentally become Dart defines. The Android package ID is permanent after publishing. Release uses that ID; debug retains `com.example.gym_management_app`. Namespace/activity source can remain unchanged. The release app installs separately from the debug app; do not uninstall the debug app or promise its session/local recovery data will migrate.

Release validation in Dart, Gradle and the release helper requires production and the approved `https://gym-api.semgroup.in/api/v1/` API. Gradle/helper require the MuscleDesk display name. Alternative HTTPS APIs and development/staging release settings fail closed. Development/staging debug configurations remain available for isolated testing.

The app exposes Privacy & support from Login, Sign Up and account/More, including during session-restoration errors. Account deletion is authenticated and password-verified. Unconfigured development builds explain missing public details; release bootstrap rejects incomplete/placeholder metadata. Public policy links open in Android's system browser, with selectable/copy fallback; other platforms retain the copy fallback.

Privacy content, publisher name, support address and retention/deletion times must describe the real service. See `play-data-safety.md` and `production-operations.md`. Do not turn development notices into a published privacy policy.

The full factual draft is now in [privacy-policy-draft.md](privacy-policy-draft.md),
with a static [HTML export](privacy-policy/index.html) and an internal
[publication handoff](privacy-policy-review.md). Finalize its explicit unknowns,
confirm control of the chosen website and obtain publication approval before
publishing the page. The historical hosted privacy checks returned 404; the new
local route does not change production. The confirmed intended URL is recorded
in release configuration, while no release guard is bypassed and no publication
approval is inferred from that configuration.

The updated draft uses India as the initial market and the owner's service/legal
retention principle. Minor-record eligibility/guardian controls, category retention
and actual fulfillment still need decisions. The intended API-host destination
and local route are now prepared, but no deployment/publication is authorized.
Configured URL syntax is not reachability or approval; keep using the URL-checked
release command and wait for a finalized, approved, actually served policy.

The URL checker rejects HTTP errors and the explicit “DRAFT — NOT APPROVED FOR
PUBLICATION” marker even on an HTTP 200 response. This content check does not
replace the operator's final policy review or authorize publication.

The helper refuses `--build` without `--check-urls`; metadata-only preflight is
still available without either flag. Use the approval-gated
[privacy-route deployment plan](privacy-policy-deployment-plan.md) when the policy
decisions are resolved. Direct Flutter/Gradle commands do not perform the helper's
live-page checks and must not be used to bypass this release workflow.

Track remaining operator decisions, provider/configuration verification and
required implementation separately in [the privacy release checklist](privacy-release-decisions.md).
The [statement evidence register](privacy-policy-evidence.md) records which policy
claims are supported by local code, supplied by the operator or unresolved.

Current local feature pass: known-minor workflow gates, optional photos, the
[approved recovery implementation](password-recovery-contract.md) and
[restricted manual-fulfillment rehearsal](manual-deletion-workflow.md) are now
implemented. Gmail's credential, real delivery, provider practices and production
parity remain unverified. Source presence or passing isolated tests do not fulfill
these release gates. Privacy is still a draft/hosted 404; no AAB against it.

## Upload signing

An owner-authorized RSA-3072 upload key now exists at `~/.muscledesk/signing/muscledesk-upload.jks` (file mode 600; directory 700). Its randomly generated passwords are stored only in Git-ignored `android/key.properties` (mode 600). Do not regenerate or replace this key. Arrange encrypted backups of both the key and signing properties outside the repository before uploading; loss of the key/password can block future uploads. Key creation and listing were verified, but no signed release bundle has yet been produced.

For a fresh setup on a different project, follow [Flutter signing guidance](https://docs.flutter.dev/deployment/android#sign-the-app). An interactive command keeps passwords out of shell history:

```sh
keytool -genkeypair -v -keystore /absolute/private/path/gym-upload.jks -keyalg RSA -keysize 3072 -validity 10000 -alias gym-upload
```

Copy `android/key.properties.example` to the Git-ignored `android/key.properties` and set its values locally. Paths are absolute or relative to `android/`. CI may use `GYM_UPLOAD_KEYSTORE`, `GYM_UPLOAD_KEY_ALIAS`, `GYM_UPLOAD_STORE_PASSWORD`, `GYM_UPLOAD_KEY_PASSWORD` instead. Never send passwords/private keys in chat or put them in release JSON. Keep encrypted, access-controlled backups of the upload key and recovery instructions. Configure Play App Signing in Play Console.

Gradle refuses a release without a real keystore, final package ID, production HTTPS settings or with the standard debug alias. The verifier also rejects the standard debug certificate. Debug/profile builds stay separate and clearly labeled. The launcher icon reuses the existing Iron Signal gym plate, including adaptive and themed-icon resources.

## Repeatable validation/build

```sh
python3 -m unittest discover -s tool -p 'test_*.py' -v
python3 tool/play_release.py --config release/production.json
python3 tool/play_release.py --config release/production.json --check-urls
python3 tool/play_release.py --config release/production.json --check-urls --build
```

Set `FLUTTER` to the installed Flutter executable if it is not on PATH. `--build` runs analysis and the full Flutter suite, builds a signed **release AAB for all default ABIs**, verifies its JAR signature/certificate, and inspects every bundled 64-bit native ELF library for 16 KB load alignment. It never deploys, commits, pushes or uploads. The AAB is `build/app/outputs/bundle/release/app-release.aab`. A standalone artifact check is available with `--verify-bundle PATH`.

Also run Dart formatting checks. Release metadata guards intentionally prevent generating a distributable bundle while public identity/signing details are deferred. A successful debug APK is not release validation.

The signature verifier uses strict JDK verification, rejects wholly unsigned
archives, unsigned added payload and duplicate ZIP entries, and rejects expired
or not-yet-valid signing-certificate warnings. It accepts only the ordinary
untrusted-chain warning of a self-signed upload key. This closes the reproduced
case where ordinary `jarsigner -verify` returned 0 after an unsigned file was
appended. See [the JDK warning/exit-code contract](https://docs.oracle.com/en/java/javase/22/docs/specs/man/jarsigner.html#errors-and-warnings).

## Play Console / final release gates

If Python on macOS has no configured CA store, supply an existing trusted bundle with `--ca-file /etc/ssl/cert.pem` (or your managed CA bundle). Do not disable certificate verification. URL checks reject non-HTTPS redirects and do not send credentials.

- Verify final app ID/name/version, launcher icon, signing certificate and production API in the built release artifact. Keep version codes increasing after uploads.
- Verify target SDK (current installed Flutter defaults to API 36), all required ABIs, 16 KB native packaging/runtime compatibility and Android edge-to-edge/keyboard behavior. ELF checks alone do not prove runtime compatibility. Follow [Google target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878) and [16 KB guidance](https://developer.android.com/guide/practices/page-sizes).
- Publish a public, accessible HTML privacy policy; configure it in the app/build and Play Console. Complete accurate Data Safety declarations, content rating, target audience and all applicable app-content questionnaires. Review actual data handling by hosting, MongoDB and Cloudinary providers.
- The hosted deletion status route returns authenticated-access-required (401 without credentials), and the external page returns 200 with a request form. This does not verify a saved request. The MuscleDesk branding correction is prepared in local backend source/tests and verified in a local browser, but is not deployed. Deploy it only through separately approved backend work; verify intake via both paths in an isolated account, and establish actual fulfillment, response deadlines and approved retention. Do not mark requests complete just to satisfy a checklist. No production submission was made during readiness work.
- Supply reviewer access through Play Console using a dedicated synthetic gym/account. Do not expose real member data in screenshots, demonstrations or review credentials.
- Prepare the store listing, screenshots, feature graphic and public support details. No store assets should misrepresent implemented roles, notifications or online payment collection.
- Upload to internal testing, run Play pre-launch reports and test the installed **Play-delivered release** across representative phones/Android versions, offline/restart/session and financial recovery scenarios. Conditional closed-testing requirements depend on the developer account; new personal accounts may need 12 opted-in testers for 14 continuous days.
- Resolve production backups/restore proof, security/authorization review, monitoring and deletion fulfillment before public launch. See the operations runbook. No Play approval or production readiness is certified by local tests alone.

## MuscleDesk scope update

Final display name is MuscleDesk. See [scope cleanup and release blockers](scope-cleanup.md) and [current release-candidate findings](release-candidate.md). Debug/internal identifiers remain unchanged. The approved new password-recovery contract is now implemented locally; see password-recovery-contract.md. The private Gmail SMTP credential, actual delivery and deployed contract remain unverified. Never reuse activation/provisioning as reset or claim an unconfirmed email/password change succeeded.
