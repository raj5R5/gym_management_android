# Gym Management System

Flutter application targeting Android and iOS. The initial foundation includes
Riverpod dependency composition, centralized routing, Material themes, public
build configuration, and a Dio client. Authentication and business features are
not implemented.

## Development

Validated SDK: Flutter 3.38.6 / Dart 3.10.7. See AGENTS.md for development rules.

```sh
flutter pub get
flutter run
```

The default debug configuration is development, without a backend URL. Startup
opens `/startup`; Continue opens the `/login` placeholder. `/home` is a temporary
navigation preview, available only in non-release development builds. It does
not authenticate a user. Other environments and release builds redirect `/home`
to `/login`.

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

The URLs above are examples, not deployed services. The app currently makes no
API requests. Invalid configuration fails at startup with a descriptive
`FormatException`. Dart defines are compiled into the app: never put secrets,
passwords, private API keys, or JWT signing secrets in them.

Native flavors and production signing are not configured. The release command
above demonstrates configuration only; existing Android release signing still
uses the starter debug key and must be addressed before distribution.

## Structure

- `lib/app/`: bootstrap, app composition, router, theme, placeholder navigation.
- `lib/core/config/`: validated environment configuration and its provider.
- `lib/core/network/`: shared Dio client and lifecycle-managed provider.
- `lib/shared/widgets/`: reusable presentation components.
- `test/`: startup/navigation, configuration, and isolated client tests.

Storage, error mapping, diagnostics, validators, formatting, and feature modules
will be added when their functionality is implemented. No empty feature folders
are created. Authentication headers, refresh behavior, and backend endpoints are
intentionally deferred.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug
```

API tests use an in-memory adapter and never contact a backend.
