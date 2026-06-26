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
./setup.sh          # installs XcodeGen, generates .xcodeproj, opens Xcode
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

## Key Directory Structure
```
AcmeBank/
  App/              ← @main entry + root view (ContentView placeholder → RootView)
  Core/             ← Auth, Networking, Notifications, Extensions  [deferred]
  Domain/           ← Models + Repository protocols                [deferred]
  Data/             ← Remote + Mock repository implementations     [deferred]
  Features/         ← Login, Home, Accounts, Transfer, Cards       [deferred]
  DesignSystem/     ← Colors, Typography, Assets.xcassets          [deferred]
  Resources/        ← Asset catalog, entitlements, privacy manifest
AcmeBankTests/      ← XCTest unit tests (one bootstrap smoke test today)
AcmeBankUITests/    ← XCUITest end-to-end tests (one launch smoke test today)
project.yml         ← XcodeGen spec — source of truth for .xcodeproj
setup.sh            ← Post-clone materialisation script
```

## Planned Architecture

### MVVM + Coordinator (deferred — future PR)
- **View** — SwiftUI `View` struct; renders `@Published` state; zero business logic.
- **ViewModel** — `final class: ObservableObject`; `@Published` state; calls repos; no SwiftUI imports.
- **Coordinator** — `ObservableObject`; owns `NavigationStack` path; creates Views+ViewModels; injects deps.
- **Repository protocols** in `Domain/`; concrete types in `Data/`; ViewModels depend only on protocols.

### Coordinator Hierarchy (deferred — future PR)
```
AppCoordinator
  ├── LoginCoordinator   (shown when no session)
  └── TabBarCoordinator  (shown after login)
        ├── HomeCoordinator
        ├── TransferCoordinator
        ├── CardsCoordinator
        └── MoreCoordinator
```

### Authentication — Okta OIDC (deferred — future PR)
- `AuthService` implements `AuthServiceProtocol` (signIn / signOut / refreshTokenIfNeeded).
- Tokens persisted to Keychain via `KeychainStore`.
- **Keychain note:** All `SecItem*` calls MUST include `kSecUseDataProtectionKeychain: true`
  for CI simulator compatibility (avoids `-34018 errSecMissingEntitlement` without a
  provisioning profile). The entitlements stub in `AcmeBank/AcmeBank.entitlements`
  covers signed-device builds; the flag covers the simulator/CI path.
- `RequestInterceptor` refreshes token before every API request; on failure posts
  `AppNotification.sessionExpired`.
- `UserSession` (value type) carries `userId`, `displayName`, `email`, `accessToken`,
  `authTimestamp`, `deviceName`. Never store in `UserDefaults`; inject it.

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
- Okta OIDC authentication (AuthService, KeychainStore, UserSession, Okta.plist)
- MVVM + Coordinator pattern (AppCoordinator, LoginCoordinator, TabBarCoordinator, etc.)
- Networking layer (APIClient, APIRouter, APIError, RequestInterceptor)
- Domain models (Account, Transaction, Customer, TransferRequest)
- Repository protocols + implementations (Remote + Mock)
- Feature screens (Login, Home/Dashboard, Accounts, Transfer, Cards, More)
- Design system (Colors.swift, Typography.swift)
- Internal Notifications (AppNotification, NotificationPublisher, NotificationKey)
- Core/Extensions (Decimal+Currency, Date+Greeting, String+Initials)
- SwiftLint config (`.swiftlint.yml`)
- CI workflow (`ios-build.yml` — GitHub Actions xcodebuild + SwiftLint)
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
