# Gym Management System

Flutter application targeting Android and iOS. The initial foundation includes
Riverpod dependency composition, centralized routing, Material themes, public
build configuration, and a Dio client. Authentication includes login, secure
session restoration, auth-aware navigation, and logout. Business features are
not implemented; authenticated home remains a placeholder.

## Development

Validated SDK: Flutter 3.38.6 / Dart 3.10.7. See AGENTS.md for development rules.

```sh
flutter pub get
flutter run
```

The default debug configuration is development, without a backend URL. Startup
opens `/startup` while the existing session controller restores the scoped
credential. No credential or failed recovery opens `/login`; successful recovery
opens authenticated `/home` in every environment. Login and logout update the
session state, and the router reacts without manual navigation from widgets.

## Build configuration

Pass public values with Dart defines:

| Define | Values / behavior |
| --- | --- |
| `APP_ENV` | `development`, `staging`, or `production`; defaults to development outside release builds |
| `API_BASE_URL` | Absolute HTTP(S) URL; HTTPS required for staging and production |

Development can omit the API URL. Requests then fail explicitly before reaching
the network. Staging, production, and all release builds require an API URL.
Release builds also require an explicit environment. URLs cannot include
credentials, query parameters, or fragments. Base paths are preserved by using
relative endpoint paths in future API services.

```sh
flutter run --dart-define=APP_ENV=development
flutter run --dart-define=APP_ENV=staging --dart-define=API_BASE_URL=https://staging.example.test/api/v1/
flutter build apk --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.test/api/v1/
```

The URLs above are examples, not deployed services. Restoration calls refresh
and `/auth/me` only when a scoped credential exists; login/logout use the
configured API. Invalid configuration fails at startup with a descriptive
`FormatException`. Dart defines are compiled into the app: never put secrets,
passwords, private API keys, or JWT signing secrets in them.

Native flavors and production signing are not configured. The release command
above demonstrates configuration only; existing Android release signing still
uses the starter debug key and must be addressed before distribution.

## Structure

- `lib/app/`: bootstrap, app composition, auth-aware router, theme, navigation.
- `lib/core/config/`: validated environment configuration and its provider.
- `lib/core/network/`: shared Dio client and lifecycle-managed provider.
- `lib/shared/widgets/`: reusable presentation components.
- `test/`: startup/navigation, configuration, and isolated client tests.

Authentication storage, models, services, repository, session state, and
providers live in `lib/features/auth/` and `lib/core/storage/`. Other feature
modules will be added as their functionality is implemented.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug
```

API and widget tests use fake dependencies or local test servers, never a live
backend or real credentials.


## Authentication data and session layer

The backend contract was inspected directly in `src/modules/auth/` and
`tests/integration/auth.test.js` of the backend repository. The API base URL must
include `/api/v1/`; services call relative paths such as `auth/login`.

| Endpoint | Mobile request | Success `data` |
| --- | --- | --- |
| POST `auth/login` | `email`, `password`, `client: mobile` | `user`, `gymAccess`, `accessToken`, `refreshToken`, `expiresIn`, `tokenType` |
| POST `auth/refresh` | `refreshToken` | `accessToken`, `refreshToken`, `expiresIn`, `tokenType` |
| GET `auth/me` | Bearer access token | `user`, `gymAccess` |
| POST `auth/logout` | `refreshToken` | `loggedOut: true` |

Success envelopes are `{success: true, data, meta: {requestId}}`. Errors use
`{success: false, error: {code, message}, meta: {requestId}}`. The server does not
return refresh expiry or session IDs in these mobile JSON responses. Mobile
requests send no Origin/cookie credentials; browser refresh cookies are a
separate backend transport and are not implemented here. Password whitespace is
preserved. An account can have no gym access or multiple grants with different
roles; there is no account-wide role inferred by the client.

`authApiServiceProvider` uses the existing public `apiClientProvider` for auth
endpoints. Future protected feature services must use
`authenticatedApiClientProvider`. Each service should convert Dio errors into
safe typed failures before exposing them to controllers. Neither client logs
credentials. Auth and protected requests disable automatic HTTP redirects,
including per-request attempts to enable them on the protected client. Redirect
responses are returned as failures; the client does not forward bearer tokens.

`sessionControllerProvider` is a manual Riverpod Notifier. It starts in
`SessionInitial`; `GymApp` requests restoration once for each initial session
controller lifecycle, after widget/provider initialization. Its methods are
`restoreSession`, `login`, `logout`, and `refreshSession`. State explicitly
represents loading/restoring, unauthenticated, authenticated identity, and a safe
error. Access/refresh credentials are never included in controller state.
GoRouter subscribes to session changes through a disposed-with-router notifier,
keeping the same router instance. Initial/restoring/refreshing states show
`/startup`; login loading keeps the form disabled; authenticated login/startup
routes redirect to `/home/dashboard` for active admins, or `/home` otherwise. Logout has an explicit loading operation, blocks
repeat calls, and stays on the home placeholder until cleanup finishes, then
routes to login. Repository bearer blocking still happens immediately. Safe
errors are displayed on login, including failed restoration or logout cleanup.
Unknown routes retain a recoverable not-found page once restoration finishes.

The login page validates email/password, trims only email, offers labelled
password visibility controls, and never navigates manually or accesses storage.
The home placeholder uses existing session identity and makes no extra API call.

Only the refresh credential is persisted securely. Keys are scoped to both the
environment and normalized API URL. Access tokens remain in memory. Restoration
rotates the stored credential and retrieves `/auth/me`. Session operations and
storage writes are serialized. Rotated credentials are staged privately: the
refresh credential is persisted and `/auth/me` succeeds before the access token
and authenticated identity become usable. Concurrent refresh callers share one future and
one refresh API call. A protected `401 INVALID_AUTHENTICATION` refreshes and
retries at most once; old-token 401s join pending recovery, and a late 401 after
successful recovery reuses the new token.
Login/refresh never receive a stale bearer token. Non-replayable stream or
multipart bodies require an explicit retry by the future feature service.

All refresh failures clear local credentials and access state, including network
failures: retrying an ambiguously consumed refresh credential could trigger the
backend's replay revocation. Logout blocks bearer use immediately, waits for any
ongoing rotation, revokes the latest refresh credential, and clears local storage
even if backend revocation fails. A storage-clear failure is surfaced as a
storage error and blocks restoration of the untrusted credential in that
repository instance. Successful cleanup is required before session recovery.
If the operating system refuses deletion, the app cannot guarantee physical
removal; the error must be surfaced to the user by the future UI. In-flight
requests already sent are not recalled by local logout.

Repository disposal discards in-memory credentials and prevents new API/storage
side effects or state publication by obsolete operations. Operations already
sent to the backend or native secure storage cannot be recalled. A
Riverpod-container-owned operation queue survives repository replacement,
draining those operations before the replacement can mutate credentials. A
discarded backend rotation may require a fresh login. Independently constructed
repositories sharing storage must also share an `AuthOperationQueue`; do not
create competing session authorities or invalidate the queue independently.

### Android emulator development

```sh
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://10.0.2.2:8001/api/v1/
```

The Android emulator's `10.0.2.2` alias reaches the host machine. This URL is a
development command only, never a source-code default. Debug networking allows
cleartext only to this emulator alias. Other hosts and release builds retain
HTTPS defaults; physical-device and iOS connectivity must be configured
separately. Production and staging AppConfig validation still requires HTTPS.

Android Internet permission is included in the main manifest. Backup and device
transfer rules exclude the secure-storage credential/key files. iOS uses
this-device-only, unlocked Keychain storage and a Keychain access-group
entitlement for this app. Real-device secure-storage behavior and backend
connectivity are separate integration checks; unit tests use fakes and an
in-memory HTTP adapter, with generated non-production credentials.


## M27: Admin shell and all-branch dashboard

Active admin gym grants from the restored session determine the available gym
context. `/home/dashboard`, `/home/members`, `/home/trainers`, and `/home/more`
share an authenticated admin shell. Members and Trainers are explicitly marked
as coming in later milestones. More provides the existing identity/logout flow.
Multiple admin grants enable a gym selector restricted to those grants; the
current identity contract supplies IDs rather than display names. Other roles
retain the existing authenticated home until their own milestones.

The `admin_dashboard` feature owns typed models, a read-only repository using
`authenticatedApiClientProvider`, Riverpod query/context/async state, and
presentation widgets. No second client, token store, or session authority is
created. The existing interceptor handles 401 recovery. Dashboard failures have
explicit retry rather than automatic Riverpod retries. Replaced filter/gym
requests cannot overwrite the current provider result.

The existing endpoint is `GET /api/v1/gyms/:gymId/dashboard`, with the
`{ success, data, meta }` envelope. `data` contains `period`, `members`,
`trainers`, `subscriptions`, `payments`, and `attendance`. M27 deliberately sends
no `branchId` and shows **Whole gym · All branches**. Branch selection is deferred;
no branch-list or development bootstrap endpoint is used. The repository/query
boundary can accept future approved filters without changing presentation/API
ownership.

Date selections send inclusive `from` and `to` calendar dates as `YYYY-MM-DD`,
with at most 366 days. The default omits both dates so the backend resolves gym-local
today. The UI displays the returned period and timezone; it does not compute gym
timezone boundaries, authorization, or aggregation rules. Profile/subscription
counts are current snapshots; successful payments and completed visits use the
selected period. Checked-in members are current. INR revenue formatting uses
integer paise, integer division, and Indian digit grouping, without floating-point
money arithmetic.

The dashboard supports loading, safe errors, retry, zero-data messaging, manual
refresh and pull-to-refresh. Tests cover contract parsing, request dates, failures,
interceptor recovery, provider races/state transitions, exact money formatting,
admin navigation/logout, responsive layout, and session recovery failure. Backend
business logic, dependencies, and native configuration are unchanged by M27.

## M28: Admin member management

Members is now a functional admin section with server search/status filtering,
bounded page navigation (20 per page; API maximum 100 per page and 10,000 pages),
loading/empty/error/retry states and pull-to-refresh. The selected authorized admin
gym is reused from M27; no user-supplied tenant input is offered. Member child
routes retain the opening gym ID as context and require it to match the current
session-derived selection. Switching gym while reading/editing requires returning
to Members, rather than reusing an old member ID under the new gym.

The `features/members` module contains typed profile, summary, membership,
pagination and draft models, a repository on the existing authenticated Dio,
Riverpod query/read/mutation providers and presentation widgets. Replacement
query/gym results are ordered by Riverpod; detail providers include account/gym
scope and are disposed when unused. Saves block duplicates and discard UI results
after scope loss. Successful writes invalidate the server list/dashboard/summary,
without inventing local records. Member routes retain their widget subtree offstage
behind startup during access-token recovery, preventing a refresh from discarding
an in-progress form. Restoration, logout and failed-refresh redirects are unchanged.

Existing production endpoints consumed (all under `/api/v1/gyms/:gymId`):

- `GET /members`: `page`, `limit`, optional `search`/`status`; `data` is the
  member DTO array, `meta.pagination` is `{ page, limit, total }`.
- `GET /members/:memberId`: member DTO for editing.
- `POST /member-onboarding`: standalone active member; no account, subscription,
  payment or trainer assignment. Request includes code/name/phone and optional
  date of birth, gender, address and emergency contact only.
- `PATCH /members/:memberId`: mutable name/phone/profile/status fields only.
  Code, tenant, user linkage and branch assignment are omitted; optional profile
  fields may be cleared using the backend's nullable PATCH contract.
- `GET /members/:memberId/summary`: Member 360 profile/current branch/trainers,
  current subscription, bounded history, successful payments/current balance and
  attendance. It supplies the details page without redundant profile requests.
- `GET /members/:memberId/memberships`: paginated history and current membership,
  with plan snapshots and successful paid/balance totals per subscription.
- `GET /members/:memberId/memberships/:subscriptionId`: opened on demand for
  read-only membership inspection, including cancellation time/reason where present.

All endpoints use `{ success, data, meta }`. The UI preserves backend-derived
membership status/current flags and exclusive end dates; it does not recalculate
eligibility, payment balances, authorization or timezone rules. Money reuses M27's
exact integer INR formatter. Only allowlisted safe failures reach presentation;
server validation is generic because the backend does not return field-level
validation details. Duplicate member codes receive specific safe feedback.

Branch selection remains unavailable. Onboarding omits `branchId`; PATCH also
omits it to preserve existing assignments. List rows show the branch ID when
provided; Member 360 supplies the current branch name. No branch list is inferred
from these records, and no development/bootstrap endpoint is used. No membership
purchase, renewal, cancellation, payment, attendance or trainer mutation UI is
implemented in M28.

Live verification uses the existing emulator command above with the real backend
on port 8001 and an authorized admin session. Check list/search/filter/pages,
onboarding, profile editing, summary/history and logout; test branch-assigned
records created through existing trusted tooling without adding app credentials.
Automated tests use synthetic records and in-memory HTTP adapters. Network writes
already sent cannot be recalled when navigating or logging out; after an ambiguous
network save failure, check Members before retrying. A retried onboarding code is
still protected by the backend's uniqueness constraint.

## M29: Admin trainer management

Trainers is now a functional admin section using the production M10 API. It offers
server search (code, name, phone and specialization), status filters, 20-record
server pages, pull-to-refresh, explicit refresh, loading/empty/error/retry states,
profile details, standalone creation and profile editing. Pagination respects the
API limits of 100 per page and page 10,000. Detail/edit routes carry the opening
gym context and refuse to reuse a trainer ID after the selected gym changes.
Branch choices remain unavailable; creation omits `branchId`, and PATCH omits it
to preserve the existing assignment. The DTO only supplies a branch ID, which is
shown honestly without inventing a name or using bootstrap endpoints.

The `features/trainers` models/repository/providers/presentation follow M28 and use
`authenticatedApiClientProvider`. Common JSON parsing, profile address and
pagination models, profile validators, pagination controls and section cards are
shared with Members. Member exports/type aliases preserve their existing API.
There is no generic CRUD framework, new HTTP client, session authority or package.
Scoped providers invalidate list/dashboard/details after successful saves and
ignore results after context loss. Separate detail/editor reads let the editor
obtain a fresh server profile without its own save invalidation discarding the
form. Trainer routes reuse M28's offstage/startup handling during token recovery,
so successful refresh preserves form input while hiding protected UI.

Exact production endpoints, all under `/api/v1/gyms/:gymId/trainers`:

- `GET /`: `page`/`limit` and optional `search`/`status`. Response `data` is the
  trainer DTO array; `meta.pagination` contains `{ page, limit, total }`.
- `GET /:trainerId`: one trainer DTO.
- `POST /`: required `trainerCode`, `firstName`, `lastName`, `phone`; supported
  optional `status` (server default active), birth date, gender, address and
  specializations. The form supplies an explicit selected status, initially active.
- `PATCH /:trainerId`: mutable names/phone/status and optional profile fields.
  Nullable birth date/gender/address/specializations may be cleared. Trainer code,
  gym ID, account linkage, roles, permissions and branch are never request inputs.

Responses use `{ success, data, meta }`; POST returns 201, reads/PATCH return 200.
The DTO contains id, gymId, trainerCode, names, phone, status, optional branchId,
birth date, gender, address, specializations, createdAt/updatedAt, and optional
userId. Account IDs are deliberately not retained/displayed because no useful
account display/provisioning workflow is part of M29.

Codes use 2–32 letters/digits/underscores/hyphens and server uppercase normalization.
Names allow 1–80 characters, phones 7–15 digits within 25 allowed characters,
birth dates strict nonfuture `YYYY-MM-DD`, and gender the existing five-value enum.
An optional address requires line1/city/two-uppercase-letter countryCode, with
optional line2/state/postalCode. Specializations use up to 10 case-insensitively
distinct entries of 1–80 characters. The form uses one entry per line so commas
remain literal. Blank specialization input clears the field on edit; the API also
supports explicit empty lists. Client checks improve feedback; backend validation
and authorization remain authoritative.

No account/grant, assignment, membership, payment or attendance workflow is created.
Duplicate codes receive a safe specific error; generic backend validation has no
field-level details. An ambiguous network/server save failure tells the admin to
check Trainers before retrying without changing the code. Saves are not retried
by Riverpod; the existing interceptor remains responsible for its one 401 retry.

For live verification, run the existing development emulator command above against
port 8001 with an authorized admin session; verify list/search/filter/pagination,
create/edit/details/nullable clearing, refresh and logout. Automated tests use
synthetic DTOs and in-memory adapters. No credentials are included in the app.

## M30: Admin membership and payment operations

From Member Details, open **Membership & payments** for current membership,
20-record paginated history, server-provided paid/balance totals and successful
payment history. Membership details include cancellation metadata and renewal
association. Existing member models, M23 read providers, section cards, pagination
and integer INR formatting are reused. The new `features/memberships` repository
and scoped Riverpod providers use the existing authenticated Dio and interceptor.
No dependencies, native configuration, auth core or backend files are changed.

All endpoints below are under `/api/v1/gyms/:gymId` and return
`{ success, data, meta }`. Collection pagination is `meta.pagination` with
`{ page, limit, total }`:

- `GET /membership-plans?page=...&limit=20&status=active`: plan array with
  `id`, `gymId`, `name`, `durationDays`, integer-paise **`price`**, `status`,
  optional `description`, and server timestamps. Plans are selected from this
  paginated authenticated list. Admin plan management is available directly from Plans.
- `GET /members/:memberId/memberships?page=...&limit=20` (M23):
  `{ member, currentMembership, subscriptions }`, with plan snapshots,
  backend-derived status/current flags and per-subscription `paymentSummary`
  containing `totalSuccessfulPaidPaise` and `remainingBalancePaise`.
- `GET /members/:memberId/memberships/:subscriptionId` (M23):
  `{ subscription, paymentSummary }`, including cancellation time/reason and
  predecessor relationship. Ownership is verified before renewal.
- `GET /members/:memberId/summary` (existing M20): reused cached Member 360 for
  identity and backend-derived overall successful payment count/total. Flutter
  does not sum a paginated payment list to invent a total.
- `POST /member-memberships` (M22, 201): `{ memberId, planId }`, optionally
  `payment: { enabled: true, amountPaise, method, paidAt, reference? }`.
  Response `data` is `{ subscription, payment: paymentDto | null }`. The form
  omits `startDate`; the backend defaults it to UTC today and computes the end
  date. Purchase review precedes explicit confirmation. A payment is recorded
  atomically with the subscription, with `paidAt` captured at review time.
- `GET /payments?page=...&limit=20&memberId=...&status=succeeded` (M14): payment
  array with IDs/scope, `subscriptionId`, `amountPaise`, `status`, `paymentMethod`,
  `paidAt`, optional `transactionReference`, `notes`, `recordedByUserId`, and
  server timestamps. The UI shows amount, method, reference, UTC time and a link
  to the associated membership. Recorder IDs are safely parsed but not displayed
  as names because the contract does not expose recorder display information.
- `POST /members/:memberId/memberships/:subscriptionId/cancel` (M23, 200):
  `{ cancellationReason?: trimmedString }`, maximum 500 characters. Explicit
  confirmation explains that history is preserved and no refund is created.
  The response is the full subscription DTO; the server owns idempotency.
- `POST /subscriptions/:subscriptionId/renew` (M15, 201): `{}` after a fresh
  member-scoped M23 ownership read. Confirmation explains that current plan
  terms, predecessor, dates and eligibility are server-resolved. The response
  is the new subscription DTO. Renewal does not record a payment in this UI.

Subscription DTOs retain `membershipPlanId`, `previousSubscriptionId`, dates,
`status`, `isCurrentlyActive`, `planNameSnapshot`, `durationDaysSnapshot`,
`pricePaiseSnapshot`, and optional cancellation fields. Dates remain UTC
`[startDate, endDate)`; an active-status future record may be not-current. Flutter
does not infer eligibility or recompute dates, balances, overlap or authorization.

Manual methods are exactly `cash`, `upi`, `bank_transfer`, `card`, `other`.
UPI/bank-transfer/card references are required; cash/other references are optional.
Provided references use the backend's 3–120 character allowlist. Currency input
is converted with integer arithmetic only, permits up to two decimals and rejects
amounts outside 1–1,000,000,000 paise. There is no gateway, refund, payment edit,
delete or separate payment-write workflow. Plan terms can change after selection;
the backend resolves and validates them at submission, and the UI displays the
actual server result.

Scoped mutations prevent duplicate submissions, ignore results after gym/account
changes or logout/relogin, and refresh existing summary/history/detail/dashboard
caches. Riverpod never retries writes. The existing interceptor still handles its
single authenticated 401 recovery/replay. Transport/server failures and malformed
write success responses are explicitly uncertain. Another write is blocked until
an explicit successful membership/payment history recheck; inspect both histories
before reviewing another attempt. This is not an idempotency-key mechanism, and
an app restart/sign-in starts a new local session: always check history after an
uncertain outcome. Read failures have safe messages, retry and refresh controls.

Branch selection remains deferred; no branch parameter, bootstrap endpoint or
arbitrary branch input is used. Paid time is review time; custom paid dates,
backdated starts and payments on renewal are future work. Plan deletion is not supported by M12. No future
attendance, assignment, staff or member self-service UI is included.

For live verification, use the existing Android emulator development command
against `http://10.0.2.2:8001/api/v1/` with your authorized admin session. Verify an
active member/plan, unpaid purchase, exact partial/full cash and referenced digital
payments, refreshed histories, cancellation/no refunds, renewal, server conflicts,
back/logout and session refresh. Purchase/renewal require the backend's existing
transaction-capable MongoDB setup. Automated tests use synthetic DTOs/adapters;
no real credentials or payment credentials are included.

### M30 extension: Admin membership plan management

Plans in the Admin navigation lists active and inactive plans in 20-record server pages,
with name, optional description, duration, exact INR price, status, pull-to-refresh,
loading, empty, safe error and retry states. Create/edit forms use M12 only:

- `GET /api/v1/gyms/:gymId/membership-plans?page=...&limit=20`: no status filter for management.
- `GET /api/v1/gyms/:gymId/membership-plans/:planId`: fresh edit DTO.
- `POST /api/v1/gyms/:gymId/membership-plans`: `name`, `durationDays`, integer-paise `price`,
  `status` and optional `description`; 201 with the plan DTO.
- `PATCH /api/v1/gyms/:gymId/membership-plans/:planId`: the same mutable fields; 200 with
  the plan DTO. Blank edited description sends `null` to clear it. ID, gym scope,
  normalized name and timestamps are never included in mutation bodies.

M12 permits duration 1–3650 days, price 0–1,000,000,000 paise (free plans supported),
active/inactive status, name up to 120 characters and optional description up to
2000 characters. Backend name normalization, uniqueness and admin authorization
remain authoritative. The client sends only documented fields and never logs tokens.
There is no DELETE operation, new client, package or native/backend change.

The empty purchase screen says “No active membership plans. Create a plan before
purchasing a membership.” Its create action opens the same form; success returns
and reloads active plans, without automatically selecting a plan or purchasing.
Creating an inactive plan leaves the active-plan list empty by design. Failed saves
keep entered values, surface safe errors and never automatically retry. Uncertain
saves block another write until an explicit plan recheck; inspect the management
list before retrying, particularly after a restart or new sign-in.

Plan pages preserve forms during token refresh, verify selected gym/session scope,
and ignore stale saves after logout/relogin. Existing logout, Dashboard, Members, Trainers and More remain intact.
Admin navigation is Dashboard | Members | Trainers | Plans | More. Live plan creation/editing still needs
verification with an authorized admin; automated tests use synthetic DTOs/adapters.

### M30 navigation refinement

Membership Plans is a first-class Admin destination alongside Dashboard, Members,
Trainers and More. Canonical routes are `/home/plans`, `/home/plans/new?gymId=...`
and `/home/plans/:planId?gymId=...`. Create/edit share the existing M12 models,
repository, providers and forms. Saving from the Plans list returns to the refreshed
list with success feedback; back navigation returns to the list without saving.
The More shortcut remains a secondary link, and More/logout works as before.

Purchase stays under Member Details → Membership & payments → Purchase membership.
Its empty-plan shortcut opens the canonical plan creation form. Saving returns to
purchase and reloads active plans without automatically selecting or purchasing.
Plan lifecycle is Active/Inactive through PATCH; no delete operation exists.
Five Material navigation destinations are verified at 320px width with enlarged
text. Live testing should cover direct Plans navigation, create/edit/status changes,
empty-purchase creation/return, and existing Dashboard/Members/Trainers/More/logout.

### M31: Admin attendance operations

Attendance is temporarily parked pending biometric/device/automated attendance
integration design. It has no Admin drawer entry, app-bar shortcut or bottom
navigation entry. Dashboard, Members, Trainers, Plans and More remain available.
The implementation and tests are retained, with no backend changes. Existing
Dashboard/member attendance metrics remain unchanged. Parked routes are
`/home/attendance` and `/home/attendance/check-in?gymId=...`. Back from the root
returns to Dashboard; the member picker returns to Attendance. More/logout and
existing auth restoration/refresh guards are retained.

The typed attendance repository uses the existing authenticated Dio only:

- `GET /api/v1/gyms/:gymId/attendance/today?page=...&limit=20`, optionally
  `status=open|completed` and a trusted selected `memberId`. M19 returns
  `{success, data: {date, timezone, summary, visits}, meta: {requestId, pagination}}`.
  Summary fields are `totalVisits`, `completedVisits`, `currentlyCheckedIn` and
  `uniqueMembers`, reflecting the server filters across all pages. Visit fields
  are `id`, `memberId`, `memberCode`, `memberName`, `branchId`, `branchName`,
  `subscriptionId`, `checkInAt`, `checkOutAt`, `status`, `durationMs`.
- `GET /api/v1/gyms/:gymId/attendance?page=...&limit=20&status=open`. M16 returns
  an array of full attendance DTOs and `meta.pagination: {page, limit, total}`.
  It intentionally has **no date filter**, keeping older/overnight open visits
  actionable: M19 today alone excludes them. Full DTOs contain `id`, `gymId`,
  `memberId`, `branchId`, `subscriptionId`, `status`, `checkInAt`, `checkOutAt`,
  `durationMs`, `recordedByUserId`, `createdAt` and `updatedAt`. Open member identity
  reuses the existing scoped member profile provider because M16 has no names.
- `POST /api/v1/gyms/:gymId/attendance/check-in`: exactly `{memberId, branchId}`;
  201 with a full open attendance DTO. The controller freshly reads the selected
  member using the existing member repository, verifies the session/gym is still
  current, and takes the assigned branch from that trusted profile.
- `POST /api/v1/gyms/:gymId/attendance/:attendanceId/check-out`: `{}`; 200 with
  a full completed DTO. Timestamps, membership selection, eligibility, atomic
  lifecycle changes and duration remain entirely server-owned.

The screen shows all-date open visits, server-confirmed check-in/out results, and
paginated today's visits (completed by default). Status and member filters apply
to today's history only. Member selection/search reuses the existing member list
contract for name/member code/phone, with explicit confirmation before a write.
Both attendance lists have loading, empty, safe error/retry and refresh states.
The server's `date` and IANA `timezone` define gym today; no client day boundaries
are sent. Visit instants are displayed in the device timezone, explicitly labelled,
and durations format the integer server `durationMs`, never timestamp subtraction.

Branch selection remains deferred. Attendance reads show all branches. M19 supplies
branch names; M16 open cards display only trusted branch IDs. Members without an
assigned branch cannot check in through this UI, and receive an honest explanation.
Inactive/mismatched branches and membership eligibility remain backend decisions.
There is no branch list, bootstrap endpoint, arbitrary branch input or backend change.

Scoped Riverpod providers/controller prevent duplicate writes and ignore stale
results after gym/account changes. Writes are never retried by the controller or
repository; the existing single 401 authentication recovery/replay is preserved.
Transport/server failures or malformed write responses are uncertain and block
further writes until an explicit successful recheck of both open visits and today's
attendance. Failed rechecks keep the lock. Inspect relevant pages/filters before
another action: a successful read is not proof of absence across every page.
The local uncertainty lock lasts for the current app/session; after restart/sign-in
always inspect attendance before repeating a previously uncertain operation.

When Attendance is re-enabled, live verification is required with an authorized
Admin against `http://10.0.2.2:8001/api/v1/`: open Attendance, search an assigned member with a
valid subscription, confirm check-in, inspect the open visit, confirm checkout,
inspect completed duration, refresh/filter/page, and verify conflicts, overnight
visits, token refresh, back, existing destinations and logout. Automated tests use
synthetic fixtures/adapters and do not write real backend attendance records.

## Optional member profile photos

Camera/gallery selection, private preview recovery, authenticated uploads,
replacement/removal, and shared initials fallbacks are documented in
[Member profile photos](docs/member-photos.md). Cloudinary credentials belong
only in the backend environment; the app has no provider secrets.
