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
routes redirect to `/home`. Logout has an explicit loading operation, blocks
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
