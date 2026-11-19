# Data Safety / privacy drafting worksheet

## Deletion update — 29 October 2026 (final)

For the Console: users can request deletion in the app, on the web page or by
email; Raj reviews and fulfils requests manually with the operator tool. Account
data is deleted; records of gyms that continue to operate stay with those gyms
(unlinked); backups and logs expire under provider settings. Data is not sold or
shared beyond the service providers in policy section 5. Inventory additions:
deletion-job stage/timestamps and the requester's email, encrypted until the
completion notice is sent. Answers stay unsubmitted until deployment and upload
are authorized.

## Current evidence — 29 October 2026

Use the [current release audit](release-audit-2026-10-29.md) when completing this
inventory. Historical old-branding/404/no-real-email statements below are
superseded: the MuscleDesk deletion page now includes the email pathway and
privacy link, the privacy URL serves an unapproved draft, and controlled local
Gmail delivery was confirmed. Hosted reset delivery and operational deletion
fulfillment remain unverified. Provider processing locations, retention and
sharing classification still need evidence; no Console answers are submitted
or approved by this document.

Code-derived inventory, **not a published policy or a completed Play declaration**. Raj and `pcterajbca7772@gmail.com` are confirmed public identity/contact, with India as the initial market. Provider/processing regions, actual retention periods, deletion turnaround and deployed infrastructure/log settings remain to be confirmed. Verify against the deployed backend and provider agreements before publication.

A complete [privacy-policy draft](privacy-policy-draft.md), [HTML export](privacy-policy/index.html)
and [source evidence/publication handoff](privacy-policy-review.md) are prepared.
They remain unapproved and unpublished. The intended URL is now configured as
`https://gym-api.semgroup.in/privacy-policy`; its local route is prepared only.
Use their explicit confirmation list before finalizing this worksheet or policy.

Owner-supplied draft scope: India initially; minors are not intentionally targeted,
but under-18 member records may be entered. Confirm eligibility/guardian controls
before making audience or consent declarations. Retention follows service need
and applicable legal obligations in principle; category periods remain undecided.
Gym operations and necessary hosting/photo sharing are the stated uses, not a
verified promise that no other off-app sharing occurs. The intended API-domain
page is selected for local preparation; deployment/publication is not approved.

| Data used by implemented features | Purpose / handling to disclose |
|---|---|
| Owner/account name, email, optional personal/gym phone and gym identity | Account creation, authentication, gym administration and profile editing |
| Member/trainer names, codes, phones, optional contact/address/DOB/gender/emergency-contact/specialization fields | Gym records, identity, membership and trainer operations; distinguish other people's records from the app owner's account |
| Membership plans, date ranges and trainer assignments; historical attendance retained after retirement | Gym service administration; review applicable Play categories, including health/fitness-related use |
| Payment amounts, dates, method, references and outstanding balances | Fee recording/reconciliation; no integrated card/bank payment gateway is implemented |
| Optional owner/member photos, selected using camera/gallery | Profile identification; private device staging, authenticated API upload/delivery and backend Cloudinary processing |
| Authentication credentials | Password sent over HTTPS, backend Argon2id hash; scoped refresh credential in platform secure storage; rotating sessions |
| Pending registration/payment/renewal/photo operations | Scoped local recovery data, preserving safeguards across retries/restarts; inspect current stores and deletion handling |
| Account-deletion request/job ID, linked account, gym choices, stage, timestamps, proof digests, encrypted notice email | Manual review and fulfillment; email removed after the completion notice; minimal completed record kept for status and restore replay |
| Operational diagnostics | Safe request IDs/status/timing and backend security events; review actual VPS/proxy/database logs and retention separately |

No advertising/analytics SDK was found in this Flutter dependency audit. Do not infer that hosting/third-party providers collect no diagnostics, or select “no data collected” because data belongs to gym members. Do not describe Cloudinary data as public; existing infrastructure uses protected API delivery. Assess Google's definitions of collection, sharing and service-provider exceptions for each real provider rather than guessing questionnaire answers.

The privacy policy must identify the actual app/publisher and contact; explain data categories, purposes, required/optional fields, providers, security, retention, deletion and any required exceptions. Explain how a gym member can contact the responsible gym/operator about their record. Photos remain optional. Do not claim automated account deletion, reminders, gateway processing, end-to-end encryption, offline operation or regulatory certification that is not implemented/verified.

The approved external deletion URL is `https://gym-api.semgroup.in/account-deletion`. Read-only inspection on 27 October 2026 confirmed a public HTTPS form, but it still uses the old Gym Management branding; correct that separately before store submission. The app's protected request flow uses `/api/v1/auth/account-deletion-request`; the hosted route now responds with 401 when no credential is supplied, rather than the previous 404. These checks do not verify receipt creation or fulfillment. Both request paths require the existing password; users unable to authenticate need a verified recovery/support-assisted process. Public support details and account recovery must be finalized before launch.

Primary requirements: [User Data / privacy / Data Safety](https://support.google.com/googleplay/android-developer/answer/10144311), [account deletion](https://support.google.com/googleplay/android-developer/answer/13327111). Recheck Play Console requirements at submission time.

Local implementation update: add recovery email address, one-time message/code,
digest-only recovery records and credential revision to the inventory, plus
internal manual-review evidence references/retention decisions and cleanup state.
Gmail SMTP is the selected new delivery provider; its credential is blank and
no real email was sent. Provider retention/locations and actual delivery are not
verified. Manual fulfillment is isolated/restricted, not a production-complete
deletion service. Raj/contact are confirmed; monitoring, targets, retention and
outside-system procedures remain open. Known-DOB minor gates are implemented;
missing DOB remains unknown and guardian processing is not enabled.
