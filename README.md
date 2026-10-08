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
