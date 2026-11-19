# Owner profile

Approved 2026-10-22. This is an additive feature; owner registration, manual sign-in, credentials, member photos and all financial operations retain their existing contracts.

## API

Authenticated active administrators use `gyms/:gymId/owner-profile`. The server derives the account from the authenticated session and rechecks active gym access. A different administrator in the same gym has a different personal profile/photo; gym name and contacts are shared gym settings.

- `GET`: public identity, personal phone, gym name/contacts, protected relative photo URL/revision and completion counts.
- `PATCH`: full `displayName`, `email`, `phone`, `gymName`, `gymContactPhone`, `gymContactEmail`. Blank optional contact strings clear those values. An email change additionally requires `currentPassword`. Fields are allowlisted and validated; the user/gym/profile write is transactional. Password, role, status, access grants and timezone cannot be edited here.
- `PUT photo`: multipart `photo`, UUID-v4 `Idempotency-Key`.
- `DELETE photo`: same idempotency header.
- `GET photo/operations/:operationKey`: verifies uncertain operations.
- `GET photo?v=:revision`: authenticated JPEG bytes; no-store. Provider URLs and IDs remain private.

Completion measures six saved details: owner name, email, personal phone, photo, gym name and gym phone. The UI explicitly labels the photo optional. Completion does not gate any feature.

## Photo reuse and recovery

The backend reuses the member photo decode/re-encode, immutable Cloudinary storage, leased operation, revision/CAS transaction and durable cleanup engine. Owner records, operation/cleanup collections and the `gym_owners` namespace are separate. The member engine defaults and namespace remain unchanged. Startup creates the new indexes and runs/stops both cleanup workers.

Flutter reuses the existing picker, authenticated repository/image bytes, private photo outbox, revision receipts, fallback and photo editor. `MemberPhotoTarget.owner` gives the existing engine a distinct owner target/key; old member outbox keys remain identical. Owner images never issue a direct provider request. Account, gym, environment and API origin are part of scope; a previous profile cannot appear while a different scope loads.

The sign-up photo is optional and staged locally, without credentials. Only a successful account-registration receipt marks it eligible for handoff. After normal sign-in, the confirmed email plus environment/API and authenticated account/gym must match before it enters the existing outbox. Interrupted handoffs retain the same operation key. Uncertain uploads are resolved through the existing photo status/retry controls in Edit owner profile. An unrelated pending photo is never overwritten.

Photo saves are independent of profile text saves. Unsaved text and active operations use the established form navigation guard. Sign-in email changes verify the existing password; this feature does not implement password changes or session-token rotation.

## Release / validation

Current scope is local development and testing only; no hosted API deployment is included. The Flutter app presents a clear unavailable/retry state if the selected API does not implement the endpoint; it never simulates a saved profile. Building an APK does not deploy backend changes.

Use isolated test accounts/storage for mutation checks. Preserve actual owner data. Tests live in `test/features/owner_profile` and backend `tests/integration/ownerProfile.test.js`; existing photo and financial suites must continue to pass.
