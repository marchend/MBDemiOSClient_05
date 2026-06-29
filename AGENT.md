# AcmeBank iOS — Agent Context

## Project Overview
AcmeBank is an iOS 17+ mobile banking application built with Swift 5.10 and SwiftUI.
It follows an MVVM + Coordinator architecture, uses Okta OIDC for authentication,
and communicates with a backend BFF via `URLSession` async/await. This file is the
authoritative context document for all agents working on the project.

## Tech Stack
| Concern | Choice |
|---|---|
| Platform | iOS 17+, Swift 5.10, Xcode 16+ |
| UI | SwiftUI (`@main App`, `NavigationStack`) |
| Architecture | MVVM + Coordinator |
| Auth | Okta OIDC — `okta-mobile-swift` 2.x |
| Networking | `URLSession` + async/await |
| DI | Constructor injection (no service locator) |
| Notifications | `NotificationCenter` with typed wrappers |
| Project file | XcodeGen `project.yml` (never hand-edit `.pbxproj`) |
| Unit tests | XCTest |
| UI tests | XCUITest |
| Bundle ID | `com.acmebank.mobile` |

## How to Run Locally
```bash
./setup.sh          # installs XcodeGen, writes Config/Secrets.local.xcconfig, generates .xcodeproj
```
Manual fallback:
```bash
brew install xcodegen && xcodegen generate && open AcmeBank.xcodeproj
```

## How to Run Tests
```bash
xcodebuild test -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```
Or `Cmd+U` in Xcode on the `AcmeBank` scheme.

## Okta configuration

The app reads four Okta values at runtime from its `Info.plist`. Those
keys are wired as build-setting references — `$(OKTA_ISSUER)`,
`$(OKTA_CLIENT_ID)`, `$(OKTA_REDIRECT_URI)`, `$(OKTA_SCOPES)` — and
Xcode's `ProcessInfoPlistFile` expands them on every build. The values
come from two xcconfig files in `Config/`:

- `Config/Secrets.example.xcconfig` *(committed)* ships placeholder
  defaults (`https://placeholder.invalid/oauth2/default`,
  `PLACEHOLDER_CLIENT_ID`, …) so the project builds with no secrets
  present. `project.yml` wires this file as the base `configFiles:` for
  the `AcmeBank` target (Debug + Release).
- `Config/Secrets.local.xcconfig` *(gitignored)* is `#include?`d by the
  example file and overrides those values with real credentials.
  `setup.sh` writes this file from exported `OKTA_*` env vars at
  project-generation time; CI does the same from job-level secrets.

When `Secrets.local.xcconfig` is absent the example placeholders survive
into the built bundle. `OktaConfig.load()` recognises both the
`placeholder.invalid` URL fragment and the `PLACEHOLDER_` prefix
(alongside the legacy `__OKTA_<KEY>_UNSET__` sentinel) and returns
`.notConfigured(reason:)`, and `ContentView` pre-seeds the LoginView
with an "Okta is not configured on this build — see README." banner.

| Env var             | Example                                          |
|---------------------|--------------------------------------------------|
| `OKTA_ISSUER`       | `https://example.okta.com/oauth2/default`        |
| `OKTA_CLIENT_ID`    | `0oa1abc2DEF3ghi4JKL5`                           |
| `OKTA_REDIRECT_URI` | `com.acmebank.mobile://callback`                 |
| `OKTA_SCOPES`       | `openid profile offline_access` (space-separated)|

These four vars are consumed by `setup.sh` at project-generation time
(they get written into `Config/Secrets.local.xcconfig`); they do NOT
need to be present in the build/launch environment.

For the `LandingUITests` end-to-end happy-path test, additionally export:

| Env var                  | Purpose                                              |
|--------------------------|------------------------------------------------------|
| `OKTA_E2E_CONFIGURED`    | Set to `YES` when the build was made with real OKTA_* env vars (gates the e2e test). |
| `OKTA_TEST_USERNAME`     | Sign-in identifier typed into the Login screen.       |
| `OKTA_TEST_PASSWORD`     | Password typed into the Login screen.                 |
| `OKTA_TEST_DISPLAY_NAME` | Optional. Expected display name on the Landing screen.|

### xcconfig gotcha: `://` in URLs

A bare `//` in an xcconfig starts an end-of-line comment, so a URL like
`https://example.okta.com/...` must be escaped as
`https:/$()/example.okta.com/...` — the `$()` is an empty build-setting
reference that breaks up the `//` token without changing the resulting
string. `setup.sh` does this automatically; the committed
`Config/Secrets.example.xcconfig` shows the pattern for hand-edited files.

## Key Directory Structure
```
AcmeBank/
  App/              ← @main entry (AcmeBankApp), AppCoordinator, ContentView
  Core/             ← Auth (OktaConfig, AuthError, UserSession, KeychainStore,
                      AuthServicing, OktaAuthService), Networking, Notifications
  Domain/           ← Models + Repository protocols                [deferred]
  Data/             ← Remote + Mock repository implementations     [deferred]
  Features/         ← Login, Landing; Home, Accounts, Transfer, Cards [deferred]
  DesignSystem/     ← Colors, Typography, Assets.xcassets          [deferred]
  Resources/        ← Asset catalog, entitlements, privacy manifest
  Info.plist        ← Hand-rolled; OKTA_* keys reference $(OKTA_*) build settings
AcmeBankTests/      ← XCTest unit tests
AcmeBankUITests/    ← XCUITest end-to-end tests (Login, Landing happy path)
Config/             ← xcconfig files
  Secrets.example.xcconfig   ← committed; placeholder values + #include? of local
  Secrets.local.xcconfig     ← gitignored; written by setup.sh from OKTA_* env vars
scripts/            ← Misc dev/CI scripts (no build-phase scripts)
project.yml         ← XcodeGen spec — source of truth for .xcodeproj
setup.sh            ← Post-clone materialisation script
```

## Architecture

### Composition root (wired)
- `AcmeBankApp` (`@main`) owns a single `@StateObject AppCoordinator`
  constructed with `OktaAuthService()`, injected into the view tree via
  `.environmentObject`.
- `AppCoordinator` (`@MainActor`, `ObservableObject`) publishes a single
  `route: AppRoute` of `.login` or `.landing(UserSession)`. Initial
  route at cold launch:
    - No persisted refresh token → `.login`
    - Refresh token present AND a cached `UserSession` available
      → `.landing(session)`
    - Refresh token present but no cached `UserSession` (silent re-auth
      not yet implemented) → `.login`
- `ContentView` switches on `coordinator.route`. For `.login` it builds
  a `LoginViewModel` whose `onSignIn` closure calls
  `OktaAuthService.signIn(...)` and, on success, calls
  `coordinator.didSignIn(session)`; on `AuthError` it surfaces
  `error.userMessage`.
- `LandingView` takes a `UserSession` and renders "Welcome,
  \(displayName)" + the email. Both labels carry stable accessibility
  identifiers `landing.welcome` / `landing.email` for XCUITest.

### MVVM + Coordinator (in progress)
- **View** — SwiftUI `View` struct; renders `@Published` state; zero business logic.
- **ViewModel** — `final class: ObservableObject`; `@Published` state; calls repos; no SwiftUI imports.
- **Coordinator** — `ObservableObject`; owns navigation state; creates Views+ViewModels; injects deps.
- **Repository protocols** in `Domain/`; concrete types in `Data/`; ViewModels depend only on protocols.

### Coordinator Hierarchy (planned)
```
AppCoordinator                  ← top-level route (.login / .landing) [done]
  ├── LoginCoordinator          (NavigationStack inside .login)       [deferred]
  └── TabBarCoordinator         (shown after login, replaces .landing)[deferred]
        ├── HomeCoordinator
        ├── TransferCoordinator
        ├── CardsCoordinator
        └── MoreCoordinator
```

### Authentication — Okta OIDC
- `OktaConfig` loads `OKTA_ISSUER`, `OKTA_CLIENT_ID`, `OKTA_REDIRECT_URI`,
  `OKTA_SCOPES` from `Info.plist`. Total function: returns
  `.notConfigured(reason:)` on any failure — never traps. The
  `isConfigured` boolean accessor exists for callers that only need a
  binary yes/no (e.g. `LandingUITests` skip-gate).
- `AuthServicing` protocol (`signIn` / `hasPersistedSession` / `signOut`);
  `OktaAuthService` is the production conformer. The Okta SDK call is
  quarantined behind an internal `DirectAuthFlowDriving` seam.
  `RealDirectAuthFlow` is the ONLY type that imports `OktaDirectAuth`:
  it constructs a `DirectAuthenticationFlow(issuerURL:clientId:scopes:redirectUri:)`,
  awaits `flow.start(username, with: .password(password))`, and
  translates the resulting `Status` into the neutral `FlowOutcome`
  enum (`.success(idToken:accessToken:refreshToken:)` /
  `.mfaRequired`).
- `AuthError` is the ONLY error type that escapes `signIn`. Post-SDK-
  success failures (JWT decode → `.invalidServerResponse`; Keychain
  write → swallowed + logged) MUST be mapped or swallowed so the
  Login UI's `catch let e as AuthError` arm never falls through to a
  misleading network-error banner.
- Tokens persisted to Keychain via `KeychainStore` (`KeychainStoring`
  protocol for testability). Writes on the `signIn` success path are
  best-effort: a failure is logged but never rethrown — the session is
  still returned. Failing a write turns a one-launch cache miss into
  a sign-in failure, which is wrong.
- **Keychain note:** All `SecItem*` calls — both in `KeychainStore`
  and in any ad-hoc test query — MUST include
  `kSecUseDataProtectionKeychain: true` for CI simulator compatibility
  (avoids `-34018 errSecMissingEntitlement` without a provisioning
  profile). The entitlements stub in `AcmeBank/AcmeBank.entitlements`
  covers signed-device builds; the flag covers the simulator/CI path.
- `RequestInterceptor` refreshes token before every API request; on failure posts
  `AppNotification.sessionExpired`.
- `UserSession` (value type) carries `userId`, `displayName`, `email`, `accessToken`,
  `authTimestamp`, `deviceName`. Built by `UserSession.make(idTokenJWT:...)`
  via base64URL-decode of the JWT payload. Never store in `UserDefaults`; inject it.

### Networking (deferred — future PR)
- `APIClient` wraps `URLSession`; decodes via `.convertFromSnakeCase` + `.iso8601`.
- `APIRouter` enum expresses all endpoints with `path`, `method`, `body`, `queryItems`.
- Base URL read from `Info.plist` key `API_BASE_URL` (injected by xcconfig — never hardcode).
- HTTP 401 → `AppNotification.sessionExpired` + `APIError.unauthorized`.

### Domain Models (deferred — future PR)
`Account`, `Transaction`, `Customer`, `TransferRequest` — all `Codable` value types.

### Internal Notifications (deferred — future PR)
- `AppNotification` typed `Notification.Name` constants; `NotificationPublisher` static helper.
- Root coordinator subscribes via Combine; ViewModels never subscribe directly.

### Design System (deferred — future PR)
- **Strictly monochrome** palette: `acmeNavy` (#1B2A4A), `acmeBackground` (#F2F3F5),
  `acmeSurface` (white), `acmeText` (#1A1A1A), `acmeSubtext` (#6B7280). No semantic colours.
- Typography scale: `acmeTitle`, `acmeHeadline`, `acmeBody`, `acmeCaption`, `acmeMonoBalance`.

### Testing Conventions
- Unit (XCTest): ViewModels, repositories, extensions. Inject mock repos via constructor.
- UI (XCUITest): critical flows only (login, transfer, sign-out). Mock network at boundary
  via `-UITestMode YES` launch argument. Use `accessibilityIdentifier` for stable locators.
- Target ≥ 80% line coverage on `Core/` and `Features/`.

## Deferred Work (not in this PR)
- Silent re-auth at cold launch using the persisted refresh token (today the
  cached-session branch falls back to `.login` until this lands)
- LoginCoordinator / TabBarCoordinator decomposition under AppCoordinator
- Networking layer (APIClient, APIRouter, APIError, RequestInterceptor)
- Domain models (Account, Transaction, Customer, TransferRequest)
- Repository protocols + implementations (Remote + Mock)
- Feature screens (Home/Dashboard, Accounts, Transfer, Cards, More)
- Design system (Colors.swift, Typography.swift)
- Internal Notifications (AppNotification, NotificationPublisher, NotificationKey)
- Core/Extensions (Decimal+Currency, Date+Greeting, String+Initials)
- SwiftLint config (`.swiftlint.yml`)
- xcconfig files for API_BASE_URL injection
- Home Dashboard BFF integration (`GET /v1/home`, HomeDashboard payload)

## Git Workflow

> **Default PR target branch: `develop`.** Every feature/refactor/docs PR
> opens against `develop`. PRs are only opened against `qa`, `uat`, or
> `main` for explicit promotion PRs.

**Branch model (`develop` → `qa` → `uat` → `main`):**

| Branch  | Role                                 | Receives PRs from              | Promotes to |
|---------|--------------------------------------|--------------------------------|-------------|
| develop | Default integration branch           | feature branches               | qa          |
| qa      | First quality gate                   | develop (promotion PR)         | uat         |
| uat     | Pre-prod acceptance                  | qa (promotion PR)              | main        |
| main    | Production / release tags            | uat (promotion PR)             | tagged only |

All feature PRs MUST target `develop`. Never open a feature PR against
`qa`, `uat`, or `main`. Promotions happen via dedicated promotion PRs.
