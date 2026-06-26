# Bootstrap Plan — AcmeBank iOS

## In scope (this PR)

### Project name + tech stack decisions
- **App Name:** AcmeBank
- **Platform:** iOS 17+, Swift 5.10, SwiftUI
- **Architecture:** MVVM + Coordinator (deferred; skeleton wired for future expansion)
- **Project file:** XcodeGen `project.yml` (never hand-crafted `.xcodeproj`)
- **UI Framework:** SwiftUI (`@main App` + `ContentView`)
- **Test runner:** XCTest (unit), XCUITest target declared with a placeholder test
- **Minimum Xcode:** 16.0
- **Bundle ID:** `com.acmebank.mobile`

### Directory structure (bootstrap only)
```
AcmeBank/                          ← SwiftUI source root
  App/
    AcmeBankApp.swift              ← @main entry point
    ContentView.swift              ← Hello World placeholder view
  Resources/
    Assets.xcassets/
      AppIcon.appiconset/
        Contents.json
      Contents.json
  AcmeBank.entitlements            ← keychain-access-groups stub
  PrivacyInfo.xcprivacy            ← privacy manifest stub
AcmeBankTests/
  AcmeBankTests.swift              ← ONE trivial unit test
AcmeBankUITests/
  AcmeBankUITests.swift            ← ONE trivial UI test (app launch smoke)
project.yml                        ← XcodeGen spec
setup.sh                           ← one-shot materialisation script
.gitignore                         ← iOS / XcodeGen ignore rules
bootstrap_plan.md
CLAUDE.md
AGENT.md
README.md
```

### Files this PR creates
| File | Purpose |
|---|---|
| `project.yml` | XcodeGen declarative project spec |
| `AcmeBank/App/AcmeBankApp.swift` | `@main` SwiftUI App entry point |
| `AcmeBank/App/ContentView.swift` | Hello World placeholder `Text("AcmeBank")` |
| `AcmeBank/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | Stub AppIcon (required by `actool`) |
| `AcmeBank/Resources/Assets.xcassets/Contents.json` | Asset catalog metadata |
| `AcmeBank/AcmeBank.entitlements` | Keychain access group stub |
| `AcmeBank/PrivacyInfo.xcprivacy` | Privacy manifest stub |
| `AcmeBankTests/AcmeBankTests.swift` | One unit test — proves test runner works |
| `AcmeBankUITests/AcmeBankUITests.swift` | One UI test — app launch smoke |
| `setup.sh` | Installs XcodeGen, runs `xcodegen generate`, opens `.xcodeproj` |
| `.gitignore` | Standard iOS / XcodeGen ignore rules |
| `CLAUDE.md` | Project context for Anthropic agents |
| `AGENT.md` | Project context for other agents (identical to CLAUDE.md) |
| `README.md` | Developer quick-start |

### How to run the project locally
```bash
./setup.sh          # installs XcodeGen if missing, generates .xcodeproj, opens in Xcode
# or manually:
brew install xcodegen
xcodegen generate
open AcmeBank.xcodeproj
```
Build & run the `AcmeBank` scheme on an iOS 17+ simulator.

### How to run tests
In Xcode: `Cmd+U` on the `AcmeBank` scheme.  
From terminal (after `xcodegen generate`):
```bash
xcodebuild test -scheme AcmeBank \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

### Definition of Hello World
The app launches on an iOS 17+ simulator and displays a single centered screen
with the text **"AcmeBank"** on a white background. One unit test (`test_contentView_initializes`)
instantiates `ContentView` and passes. One UI test (`test_appLaunches`) verifies
the app launches without crashing.

---

## Out of scope — deferred to future work

- **Authentication (Okta OIDC via `okta-mobile-swift`)** — future PR
- **MVVM + Coordinator pattern** (AppCoordinator, LoginCoordinator, TabBarCoordinator, etc.) — future PR
- **RootView auth-state switching** (Login vs TabBar) — future PR
- **Networking layer** (APIClient, APIRouter, APIError, RequestInterceptor) — future PR
- **Domain models** (Account, Transaction, Customer, TransferRequest) — future PR
- **Repository protocols** (AccountRepositoryProtocol, TransactionRepositoryProtocol, etc.) — future PR
- **Data layer** (Remote API repositories + Mock repositories) — future PR
- **Features** (Login, Home/Dashboard, Accounts, Transfer, Cards, More screens) — future PRs
- **Design system** (Colors.swift, Typography.swift, custom Assets.xcassets) — future PR
- **Internal Notifications** (AppNotification, NotificationPublisher, NotificationKey) — future PR
- **Core/Auth layer** (AuthService, KeychainStore, UserSession) — future PR
- **Core/Extensions** (Decimal+Currency, Date+Greeting, String+Initials) — future PR
- **SwiftLint configuration** (`.swiftlint.yml`) — future PR
- **CI workflow** (`ios-build.yml` for GitHub Actions) — future PR
- **Okta.plist + Okta.plist.example** — future PR (Auth story)
- **xcconfig files** for API_BASE_URL injection — future PR
- **80% test coverage on Core/ and Features/**: feature-story tests — future PRs
- **XCUITest flows** (LoginUITests, TransferUITests, etc.) — future PRs
- **Home Dashboard BFF integration** (`GET /v1/home`, HomeDashboard payload) — future PR
